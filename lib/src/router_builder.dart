import 'dart:async';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:nop_annotations/nop_annotations.dart';
import 'package:source_gen/source_gen.dart';

import '../nop_gen.dart';
import 'type_name.dart';

class RouterGenerator extends GeneratorForAnnotation<RouterMain> {
  late LibraryReader reader;
  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) {
    reader = library;
    return super.generate(library, buildStep);
  }

  @override
  generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    for (var metaElement in element.metadata) {
      final meta = metaElement.computeConstantValue();
      final metaName = meta?.type?.element?.name;
      if (isSameType<RouterMain>(metaName)) {
        final root = gen(meta!);
        if (element is ClassElement) {
          final staticMethds = element.methods.where((e) => e.isStatic);
          final map = <MethodElement, RouteBuilderItemElement>{};
          for (var item in staticMethds) {
            for (var metaElement in item.metadata) {
              final meta = metaElement.computeConstantValue();
              final metaName = meta?.type?.element?.name;
              if (isSameType<RouteBuilderItem>(metaName)) {
                final part = genBuildElement(meta!, item);
                final value = map[item];
                if (value != null) {
                  value.pages.addAll(part.pages);
                } else {
                  map[item] = part;
                }
              }
            }
          }
          targetClassName = element.name;
          mainElement = root;
          return generator(root, map.values.toList());
        }
      }
    }
  }

  late String targetClassName;
  late NopMainElement mainElement;

  String generator(
      NopMainElement root, List<RouteBuilderItemElement> builders) {
    final buffer = StringBuffer();
    final bufferNav = StringBuffer();
    final memberBuffer = StringBuffer();
    final regFnBuffer = <String, String>{};

    var name = root.realClassName;
    final className = getDartClassName(name);
    final rootName = getDartMemberName(root.realMemName(dot: false));
    final restorationId = root.restoratoinId == null
        ? ''
        : 'restorationId: \'${root.restoratoinId}\',';
    memberBuffer.write('''
    late final NRouter _${root.realRouterName};
    static NRouter get ${root.realRouterName} => _instance!._${root.realRouterName};
    ''');
    genRoute(
        root, name, builders, buffer, memberBuffer, bufferNav, regFnBuffer);
    for (var entry in regFnBuffer.entries) {
      buffer.write(
          'NRouterJsonTransfrom.putToJsonFn<${entry.key}>(${entry.value});');
    }
    buffer.write('''
   _${root.realRouterName} = NRouter(
      rootPage: _$rootName,
      $restorationId
      params :params,
      extra: extra,
      groupId: groupId,
      observers: observers,
      updateLocation: updateLocation,
     );
''');

    final genBuffer = StringBuffer();
    genBuffer.write('// ignore_for_file: prefer_const_constructors\n\n');

    final navClassName = getDartClassName(root.realPathName);
    genBuffer.write('''
    class $className {
      $className._();

      static $className? _instance;
      
       static $className init({
        bool newInstance = false,
        Map<String, dynamic> params = const {},
        Map<String, dynamic>? extra,
        Object? groupId,
        bool updateLocation = false,
        List<NavigatorObserver> observers = const [],
      }) {
        if(!newInstance && _instance != null) {
          return _instance!;
        }
        final instance = _instance = $className._();
        instance._init(params, extra, groupId, observers, updateLocation);
        return instance;
      }

      void _init(
        Map<String, dynamic> params,
        Map<String, dynamic>? extra,
        Object? groupId,
        List<NavigatorObserver> observers,
        bool updateLocation,
      ) {
        $buffer
      }
      $memberBuffer
      ${root.isSameClass ? bufferNav : ''}
    }
  ''');
    if (!root.isSameClass) {
      genBuffer.write('''
    class $navClassName {
      $navClassName._();
      $bufferNav
    }
  ''');
    }
    return genBuffer.toString();
  }

  ExecutableElement? getFromJsonFn(Element? element) {
    if (element is! InterfaceElement) return null;
    return element.getMethod('fromJson') ??
        element.getNamedConstructor('fromJson');
  }

  ExecutableElement? getToJsonFn(Element? element, {String? name}) {
    if (element is! InterfaceElement) return null;
    return element.getMethod(name ?? 'toJson');
  }

  bool hasSuperType(Element? element, String name) {
    if (element is! InterfaceElement) return false;
    for (var parent in element.interfaces) {
      return parent.element.displayName == name;
    }
    return false;
  }

  void genRoute(
    Base base,
    String className,
    List<RouteBuilderItemElement> builders,
    StringBuffer routes,
    StringBuffer memberBuffer,
    StringBuffer routeNav,
    Map<String, String> regFnBuffer, {
    String currentPath = '',
  }) {
    var mainClassName = base.classCallName();

    var name = getDartMemberName(base.realMemName(dot: false));
    var routeName = '/';
    var fullName = currentPath;
    if (base.isRoot) {
      routeName = '/';
      fullName = '/';
    } else {
      // routeName = '/$name';
      routeName = name;
      if (fullName.endsWith('/')) {
        fullName += name;
      } else {
        fullName += routeName;
      }
    }
    for (var page in base.pages) {
      genRoute(page, className, builders, routes, memberBuffer, routeNav,
          regFnBuffer,
          currentPath: fullName);
    }

    FunctionTypedElement? element = base.getBuildFn();
    final isConstFn = element is ConstructorElement && element.isConst;

    if (element == null) return;

    final parameters = <String>[];
    // final parametersMessage = <String>[];
    final parametersPosOrNamed = <String>[];
    final parametersNamedUsed = <String>[];
    final parametersNamedArgs = <String>[];
    final parametersNamedQueryArgs = <String>[];
    final pathNames = <String>[];

    final jsonKey = StringBuffer();

    for (var item in element.parameters) {
      if (!mainElement.genKey && item.name == 'key') {
        continue;
      }

      final paramNote = getParamNote(item.metadata);
      final itemName = paramNote.getName(item.name);
      var paramFrom = paramNote.isQuery ? 'entry.queryParams' : 'entry.params';

      final requiredValue =
          item.isRequiredNamed && !item.hasDefaultValue ? 'required ' : '';
      final defaultValue =
          item.hasDefaultValue ? ' = ${item.defaultValueCode}' : '';
      final fot = '$requiredValue${item.type} $itemName$defaultValue';
      if (paramNote.isQuery) {
        parametersNamedQueryArgs.add("'$itemName': $itemName");
      } else {
        pathNames.add(itemName);
        parametersNamedArgs.add("'$itemName': $itemName");
      }

      var extra = StringBuffer();
      if (!item.type.isDartCoreString) {
        final type = item.type.element?.name;
        extra.write('if ($itemName is! $type?) {');
        var wrote = false;
        if (!item.type.isDartType) {
          final typeElement = item.type.element;
          final jsonFn = paramNote.fromJson ?? getFromJsonFn(typeElement);
          final itemType = typeElement?.displayName;
          final isEnum = typeElement is EnumElement;
          if (jsonFn != null) {
            final fnCall = fnName(jsonFn);
            extra.write('$itemName = $fnCall($itemName);');
            wrote = true;
          } else if (isEnum) {
            extra.write('$itemName = $itemType.values[$itemName];');
            wrote = true;
          }
          final hasToJsonFn = hasSuperType(typeElement, 'NRouterJsonTransfrom');
          if (!hasToJsonFn) {
            final toJson = getToJsonFn(typeElement, name: paramNote.toJsonName);
            var toJsonValue = 'null';
            if (toJson != null && toJson.isStatic) {
              toJsonValue = toJson.displayName;
            }
            if (itemType != null && !isEnum) {
              regFnBuffer.putIfAbsent(itemType, () => '($toJsonValue,)');
            }
          }
        }
        if (!wrote) {
          extra.write('$itemName = jsonDecodeCustom($itemName);');
        }
        extra.write('}');
      }

      jsonKey.write("var $itemName = $paramFrom['$itemName'];$extra");
      if (item.isOptionalPositional) {
        parametersPosOrNamed.add(fot);
        parametersNamedUsed.add(itemName);
        // parametersNamedUsed.add('$paramFrom[\'$itemName\']');
        continue;
      } else if (item.isNamed) {
        parametersNamedUsed.add("${item.name}: $itemName");
        // parametersNamedUsed.add('${item.name}: $paramFrom[\'$itemName\']');
        // parametersNamedArgs.add("'$itemName': $itemName");
        parametersPosOrNamed.add(fot);
        continue;
      }
      parametersNamedUsed.add(itemName);
      // parametersNamedArgs.add("'$itemName': $itemName");
      // parameters.add('$paramFrom[\'$itemName\']');
      parametersPosOrNamed.add('required ${item.type} $itemName$defaultValue');
    }
    final buffer = StringBuffer();
    buffer.writeAll(parameters, ',');
    if (buffer.isNotEmpty) {
      buffer.write(',');
    }
    buffer.writeAll(parametersNamedUsed, ',');

    var baseChild = '$mainClassName($buffer)';

    final methods = <MethodElement>{};
    final classPage = base.classElement;
    final builder = base.pageBuilderElement;
    for (var item in builders) {
      if (item.pages.contains(classPage) || item.builders.contains(builder)) {
        methods.add(item.method);
      }
    }

    final listBuffer = StringBuffer();

    // functioin call
    final isConstPage = buffer.isEmpty && isConstFn;

    if (base.allgroupList.isNotEmpty) {
      listBuffer.write('''
            groupList: const ${base.allgroupList.map((e) => e.name!).toList()},
          ''');
    }

    var constPrefix = '';
    if (isConstPage) {
      constPrefix = 'const';
    }

    final builderBuffer = StringBuffer();

    var groupParam = '';
    if (methods.isNotEmpty) {
      final builder = fnName(methods.first);
      builderBuffer.write('$builder');
    }

    var children = base.pages.map((e) {
      var memberName = getDartMemberName(e.realMemName(dot: false));
      if (mainElement.private) memberName = '_$memberName';

      return '_$memberName';
    }).toList();

    var childrenBuffer = '';
    if (children.isNotEmpty) {
      childrenBuffer = 'pages: $children,';
    }

    var memberName = name;
    final buf = StringBuffer();
    var nPage = base.isRoot ? 'NPageMain' : 'NPage';
    if (base is NopMainElement) {
      final name = fnName(base.errorBuilderElement);
      if (name != null) {
        buf.write('errorPageBuilder: $name,');
      }
    }
    if (!base.isRoot && mainElement.private) {
      memberName = '_$name';
    }

    final first = base.firstUnique;

    var owner = getDartMemberName(first.realMemName(dot: false));
    if (!base.isRoot && mainElement.private) {
      owner = '_$owner';
    }

    final groupKey = base.groupKey;

    if (base.allgroupList.isNotEmpty) {
      buf.write('useGroupId: true,');
      parametersPosOrNamed.add('required $groupKey');
    } else {
      parametersPosOrNamed.add('$groupKey');
    }

    groupParam = ', groupId: $groupKey';

    final seeGroupKey = '''
      ${base.paramDoc}/// [$groupKey]
      /// see: [NPage.newGroupKey]''';

    var prKey = 'static $nPage get $memberName => _instance!._$memberName;';

    memberBuffer.write('''
            late final $nPage _$memberName;
            $prKey
          ''');

    var pageBuilder = '';

    if (builderBuffer.isNotEmpty) {
      builderBuffer.write('($baseChild)');
    } else {
      builderBuffer.write(baseChild);
    }
    if (base.pageBuilderName != null) {
      pageBuilder =
          '${base.pageBuilderName}(entry, $constPrefix $builderBuffer)';
    } else {
      pageBuilder =
          'MaterialIgnorePage(key: entry.pageKey,entry: entry, child:$constPrefix $builderBuffer)';
    }

    final pathName =
        pathNames.isEmpty ? routeName : '$routeName/:${pathNames.join('/:')}';
    var redirectFn = fnName(base.redirectFn) ?? '';
    if (redirectFn.isNotEmpty) {
      redirectFn = 'redirectBuilder: $redirectFn,';
    }

    routes.write('''
     _$memberName = $nPage(
        $buf
        $childrenBuffer
        $listBuffer
        path: '$pathName',
        $redirectFn
        pageBuilder: (entry)  {
          $jsonKey
          return $pageBuilder;
        },
      );

      ''');

    final args = parametersNamedArgs.isEmpty
        ? ''
        : ', params: {${parametersNamedArgs.join(',')}}';

    final query = parametersNamedQueryArgs.isEmpty
        ? ''
        : ', extra: {${parametersNamedQueryArgs.join(',')}}';

    final funcName = mainElement.funcName(base.realMemName(dot: false));
    final route = mainElement.routeName(memberName);
    final router = mainElement.routeName(mainElement.routerName);

    final params = parametersPosOrNamed.isEmpty
        ? ''
        : '{${parametersPosOrNamed.join(',')}}';
    routeNav.write('''
        $seeGroupKey
        static RouterAction $funcName($params) {
          return RouterAction($route, $router$args$query$groupParam);
        }
      ''');
    //     routeNav.write('''
    // static NopRouteAction<T> $funcName<T>(
    //     {BuildContext? context, ${parametersPosOrNamed.join(',')}}) {
    // $contextBuffer
    //   return NopRouteAction(
    //       context: context, route: $route, arguments: $args);
    // }
    // ''');
  }

  NopMainElement gen(DartObject value) {
    final className = value.getField('className')?.toStringValue();
    final rootName = value.getField('name')?.toStringValue();
    final pages = value.getField('pages')?.toListValue();
    final private = value.getField('private')?.toBoolValue();
    final genKey = value.getField('genKey')?.toBoolValue();
    final navClassName = value.getField('navClassName')?.toStringValue();
    final main = value.getField('page')?.toTypeValue();
    final pagev = value.getField('page')?.toFunctionValue();

    final items = pages!.map(genItemElement).toList();
    final groupList = value.getField('groupList')?.toListValue();
    final groupListElement =
        groupList!.map((e) => e.toTypeValue()!.element!).toSet();

    final reg = value.getField('classToNameReg')?.toStringValue() ?? '';
    final restorationId = value.getField('restorationId')?.toStringValue();
    final redirectFn = value.getField('redirectFn')?.toFunctionValue();
    final errorBuilderElement =
        value.getField('errorBuilder')?.toFunctionValue();

    final element = NopMainElement(
      className: className!,
      restoratoinId: restorationId,
      classToNameReg: reg,
      redirectFn: redirectFn,
      name: rootName!,
      pages: items,
      main: main?.element,
      pageBuilderElement: pagev,
      groupList: groupListElement,
      private: private!,
      genKey: genKey!,
      navClassName: navClassName!,
      pageBuilderName: genPageBuilder(value),
      errorBuilderElement: errorBuilderElement,
    );
    for (var item in items) {
      item.parent = element;
    }
    return element;
  }

  String? genPageBuilder(DartObject value) {
    final fn = value.getField('pageBuilder')?.toFunctionValue();
    return fnName(fn);
  }

  RouteItemElement genItemElement(DartObject value) {
    final metaName = value.type?.element?.displayName;
    assert(isSameType<RouterPage>(metaName));
    final name = value.getField('name')?.toStringValue();
    var page = value.getField('page')?.toTypeValue();
    final pagev = value.getField('page')?.toFunctionValue();
    final pages = value.getField('pages')?.toListValue();
    final items = pages!.map(genItemElement).toList();
    final groupList = value.getField('groupList')?.toListValue();

    final groupListElement =
        groupList!.map((e) => e.toTypeValue()!.element!).toSet();
    final reg = value.getField('classToNameReg')?.toStringValue();
    final redirectFn = value.getField('redirectFn')?.toFunctionValue();

    final element = RouteItemElement(
      page: page?.element,
      classToNameArgCurrent: reg,
      pageBuilderElement: pagev,
      name: name!,
      pages: items,
      redirectFn: redirectFn,
      groupList: groupListElement,
      pageBuilderName: genPageBuilder(value),
    );
    for (var item in items) {
      item.parent = element;
    }
    return element;
  }

  RouteBuilderItemElement genBuildElement(
      DartObject meta, MethodElement method) {
    final pages = meta.getField('pages')?.toListValue();
    final builders = <ExecutableElement>[];
    final pagesElement = pages!
        .map((e) {
          final element = e.toTypeValue()?.element;
          if (element == null) {
            final builder = e.toFunctionValue();
            if (builder != null) {
              builders.add(builder);
            }
          }
          return element;
        })
        .whereType<Element>()
        .toList();
    return RouteBuilderItemElement(
        pages: pagesElement, builders: builders, method: method);
  }
}

class NopMainElement with Base {
  NopMainElement({
    this.className = '',
    this.restoratoinId,
    this.classToNameReg = '',
    this.routerName = 'router',
    this.name = '',
    this.pages = const [],
    this.private = true,
    this.genKey = false,
    this.navClassName = '',
    this.main,
    this.pageBuilderElement,
    this.groupList = const {},
    this.pageBuilderName,
    this.redirectFn,
    this.errorBuilderElement,
  });
  final String className;
  @override
  final String classToNameReg;
  @override
  final String name;
  @override
  final Base? parent = null;
  @override
  bool get isRoot => true;

  final bool genKey;
  final String navClassName;
  final String routerName;
  final String? restoratoinId;

  bool get isSameClass => realPathName == realClassName;

  String get realClassName => className.isEmpty ? 'Routes' : className;

  String get realPathName => navClassName.isEmpty ? 'NavRoutes' : navClassName;
  String get realRouterName => routerName.isEmpty ? 'router' : routerName;

  String funcName(String name) {
    if (isSameClass) {
      return 'nav${getDartClassName(name)}';
    }
    return getDartMemberName(name);
  }

  String routeName(String name) {
    if (!isSameClass) {
      return '$realClassName.$name';
    }
    return name;
  }

  @override
  final List<RouteItemElement> pages;

  /// 除了root route其他都生成私有字段
  final bool private;
  final Element? main;
  @override
  Element? get page => main;
  @override
  final ExecutableElement? pageBuilderElement;
  final ExecutableElement? errorBuilderElement;

  @override
  final Set<Element> groupList;
  @override
  final String? pageBuilderName;
  @override
  final ExecutableElement? redirectFn;
}

class RouteItemElement with Base {
  RouteItemElement({
    this.name = '',
    this.page,
    this.classToNameArgCurrent,
    this.pageBuilderElement,
    this.pages = const [],
    this.groupList = const {},
    this.pageBuilderName,
    ExecutableElement? redirectFn,
  }) : _redirectFn = redirectFn;
  @override
  final String name;

  final String? classToNameArgCurrent;
  @override
  String get classToNameReg {
    if (classToNameArgCurrent == null) {
      return parent?.classToNameReg ?? '';
    }
    return classToNameArgCurrent!;
  }

  @override
  late final Base? parent;

  /// 类型: Widget
  @override
  final Element? page;
  @override
  final ExecutableElement? pageBuilderElement;

  @override
  final List<RouteItemElement> pages;

  @override
  final Set<Element> groupList;
  @override
  final String? pageBuilderName;

  final ExecutableElement? _redirectFn;

  @override
  ExecutableElement? get redirectFn {
    return _redirectFn ?? parent?.redirectFn;
  }
}

mixin Base {
  String get name;
  Element? get page;
  ExecutableElement? get pageBuilderElement;

  Base? get parent;
  ClassElement? get classElement => page as ClassElement?;
  bool get isRoot => false;

  ExecutableElement? get redirectFn => null;
  // String get fullName {
  //   if (isRoot || parent == null) return '';
  //   return '${parent!.fullName}/$realName';
  // }

  String get classToNameReg;

  String? get _className {
    final name = classElement?.name;

    if (name != null && name.isNotEmpty && classToNameReg.isNotEmpty) {
      return name.replaceAll(RegExp(classToNameReg), '');
    }
    return name;
  }

  /// 真实类名，不可改变
  String classCallName({bool dot = true}) {
    return classElement?.name ?? fnName(pageBuilderElement!, dot: dot)!;
  }

  /// 变量名称
  String realMemName({bool dot = true}) {
    if (name.isNotEmpty) {
      return name;
    }
    return _className ??
        fnName(pageBuilderElement!, dot: dot, reg: classToNameReg)!;
  }

  List<RouteItemElement> get pages;
  String? get pageBuilderName;

  List<String> get groupListList => groupList.map((e) => e.name!).toList();

  Set<Element> get groupList;
  Set<Element> get allgroupList {
    final first = firstUnique;
    if (first.groupList.isEmpty) return {};
    final parentAllUnipue = first.groupList;
    final all = getChilrengroupList(first);
    return parentAllUnipue..addAll(all);
  }

  static Set<Element> getChilrengroupList(Base base) {
    final elements = <Element>{};
    elements.addAll(base.groupList);
    elements.addAll(base.pages.expand(getChilrengroupList));
    return elements;
  }

  ExecutableElement? getBuildFn() {
    if (pageBuilderElement != null) return pageBuilderElement;

    for (var constructor in classElement!.constructors) {
      if (constructor.name.isEmpty) {
        return constructor;
      }
    }

    return null;
  }

  String? _groupKey;
  Base get firstUnique {
    Base? base = this;
    Base notEmptyParent = this;
    while (base != null) {
      if (base.groupList.isNotEmpty) {
        notEmptyParent = base;
      }
      base = base.parent;
    }
    return notEmptyParent;
  }

  static const defaultKey = 'groupId';
  String? get groupKey {
    if (_groupKey != null) return _groupKey;

    final element = getBuildFn();
    if (element == null) return null;

    final allnames = element.parameters.map((e) {
      final paramNote = getParamNote(e.metadata);
      return paramNote.getName(e.name);
    });

    var name = defaultKey;
    while (true) {
      if (!allnames.contains(name)) {
        return _groupKey = name;
      }
      name = '$defaultKey$id';
    }
  }

  String get paramDoc {
    final element = getBuildFn();
    if (element == null) return '';
    final buffer = StringBuffer();
    for (var item in element.parameters) {
      final paramNote = getParamNote(item.metadata);
      final name = paramNote.getName(item.name);

      if (name != item.name) {
        final clsField = getMember(element, item.name);
        buffer.writeln('/// [$name] : [$clsField]');
      }
    }

    return buffer.toString();
  }

  var _idIndex = 0;
  int get id {
    return _idIndex += 1;
  }
}

class RouteBuilderItemElement {
  const RouteBuilderItemElement(
      {this.pages = const [], this.builders = const [], required this.method});
  final List<Element> pages;
  final MethodElement method;
  final List<ExecutableElement> builders;
}

Builder routerMainBuilder(BuilderOptions options) =>
    SharedPartBuilder([RouterGenerator()], 'router');

extension on DartType {
  bool get isDartType {
    return isDartCoreBool ||
        isDartCoreInt ||
        isDartCoreDouble ||
        isDartCoreNum ||
        isDartCoreString ||
        isDartCoreSet ||
        isDartCoreList ||
        isDartCoreIterable ||
        isDartCoreMap;
  }
}
