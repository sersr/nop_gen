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
      final metaName = meta?.type?.getDisplayString(withNullability: false);
      if (isSameType<RouterMain>(metaName)) {
        final root = gen(meta!);
        if (element is ClassElement) {
          final staticMethds = element.methods.where((e) => e.isStatic);
          final map = <MethodElement, RouteBuilderItemElement>{};
          for (var item in staticMethds) {
            for (var metaElement in item.metadata) {
              final meta = metaElement.computeConstantValue();
              final metaName =
                  meta?.type?.getDisplayString(withNullability: false);
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
         List<NavigatorObserver> observers = const [],
      }) {
        if(!newInstance && _instance != null) {
          return _instance!;
        }
        return _instance = $className._().._init(params, extra, groupId, observers);
      }

      void _init(
        Map<String, dynamic> params,
        Map<String, dynamic>? extra,
        Object? groupId,
        List<NavigatorObserver> observers,
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

    FunctionTypedElement? element;
    var isConst = false;
    if (base.pageBuilderElement != null) {
      element = base.pageBuilderElement!;
    } else {
      for (var constructor in base.classElement!.constructors) {
        if (constructor.name.isEmpty) {
          element = constructor;
          isConst = constructor.isConst;
        }
      }
    }
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

      final paramNote = getParamNote<Param>(item.metadata);
      var paramFrom = paramNote.isQuery ? 'entry.queryParams' : 'entry.params';
      final itemName = paramNote.getName(item.name);

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
        final type = item.type.getDisplayString(withNullability: false);
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
              toJsonValue = toJson.getDisplayString(withNullability: false);
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

    final pageConst = buffer.isEmpty && isConst && base.allgroupList.isEmpty;
    var constPre = pageConst ? '' : 'const ';

    /// removed
    // if (base.list.isNotEmpty) {
    //   listBuffer.write('''
    //     list: $constPre ${base.listList},
    //   ''');
    // }
    if (base.allgroupList.isNotEmpty) {
      listBuffer.write('''
            groupList: $constPre ${base.allgroupList.map((e) => e.name!).toList()},
          ''');
    }
    // if (haslist) {
    //   listBuffer.write('preRun: (list) {');
    // }
    // for (var item in base.groupList) {
    //   listBuffer.write('list<${item.name}>(shared: false);');
    // }
    // for (var item in base.list) {
    //   listBuffer.write('list<${item.name}>();');
    // }
    // if (listBuffer.isNotEmpty) {
    //   listBuffer.write('},');
    // }

    var constPrefix = '';
    if (pageConst) {
      constPrefix = 'const';
    }

    final builderBuffer = StringBuffer();

    var groupParam = '';
    if (methods.isNotEmpty) {
      final builds = methods.map((e) => '$targetClassName.${e.name}').toList();
      if (pageConst) {
        builderBuffer.write('''builders: $builds,''');
      } else {
        builderBuffer.write('''builders: const $builds,''');
      }
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
    var nPage = base.isRoot ? 'NPageMain' : 'NPage';
    if (!base.isRoot && mainElement.private) {
      memberName = '_$name';
    }
    final buf = StringBuffer();
    var seeGroupKey = '';
    // final contextBuffer = StringBuffer();

    if (base.allgroupList.isNotEmpty) {
      final first = base.firstUnique;

      var owner = getDartMemberName(first.realMemName(dot: false));
      if (!base.isRoot && mainElement.private) {
        owner = '_$owner';
      }

      // final isCurrent = base == first;
      // final groupOwner = '() => _$owner';
      final groupKey = base.groupKey;
      final groupOwner = first == base ? 'true' : '() => $owner';
      // groupOwnerLate:  $groupOwner,
      // groupKey: '$groupKey',
      buf.write('''
            groupOwner: $groupOwner,
          ''');

      parametersPosOrNamed.add('required $groupKey');
      // parametersNamedArgs.add("'$groupKey': $groupKey");
      groupParam = ', groupId: $groupKey';
      builderBuffer.write('group: entry.groupId,');
      constPrefix = '';
      seeGroupKey = '''
      /// [$groupKey]
      /// see: [NPage.newGroupKey] and [NPage.resolveGroupId]''';
    }

    var prKey = 'static $nPage get $memberName => _instance!._$memberName;';

    memberBuffer.write('''
            late final $nPage _$memberName;
            $prKey
          ''');

    var pageBuilder = '';
    final nopWidget = ''' Nop.page(
        $listBuffer
        $builderBuffer
        child: $baseChild,
        ),''';

    if (base.pageBuilderName != null) {
      pageBuilder = '${base.pageBuilderName}(entry, $constPrefix $nopWidget)';
    } else {
      pageBuilder =
          'MaterialIgnorePage(key: entry.pageKey,entry: entry, child:$constPrefix $nopWidget)';
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
    final metaName = value.type?.getDisplayString(withNullability: false);
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

String? fnName(ExecutableElement? fn, {bool dot = true, String reg = ''}) {
  if (fn != null) {
    if (fn.enclosingElement is InterfaceElement) {
      final cls = fn.enclosingElement as InterfaceElement;
      var name = cls.name;
      if (reg.isNotEmpty) {
        name = name.replaceAll(RegExp(reg), '');
      }
      if (dot) {
        return '$name.${fn.name}';
      }

      return '${name}_${(fn.name)}';
    }
    if (reg.isNotEmpty) {
      return fn.name.replaceAll(RegExp(reg), '');
    }
    return fn.name;
  }
  return null;
}

ParamNote getParamNote<T>(List<ElementAnnotation> list) {
  for (var item in list) {
    final meta = item.computeConstantValue();
    final metaName = meta?.type?.getDisplayString(withNullability: false);
    if (isSameType<T>(metaName)) {
      final name = meta!.getField('name')?.toStringValue();
      final isQuery = meta.getField('isQuery')?.toBoolValue();
      final fromJson = meta.getField('fromJson')?.toFunctionValue();
      final toJson = meta.getField('toJson')?.toFunctionValue();
      final toJsonName = meta.getField('toJsonName')?.toStringValue();
      if (name != null && isQuery != null) {
        return ParamNote(name, isQuery, fromJson, toJson, toJsonName);
      }
    }
  }
  return ParamNote('', true, null, null, null);
}

class ParamNote {
  ParamNote(
      this.name, this.isQuery, this.fromJson, this.toJson, this.toJsonName);
  final String name;
  final bool isQuery;
  final ExecutableElement? fromJson;
  final ExecutableElement? toJson;
  final String? toJsonName;

  String getName(String baseName) {
    if (name.isEmpty) {
      return baseName;
    }
    return name;
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

  List<String> get allArgumentNames {
    final parametersMessage = <String>[];
    if (pageBuilderElement != null) {
      for (var item in pageBuilderElement!.parameters) {
        parametersMessage.add(item.name);
      }
    } else {
      for (var constructor in classElement!.constructors) {
        if (constructor.name.isEmpty) {
          for (var item in constructor.parameters) {
            parametersMessage.add(item.name);
          }
          return parametersMessage;
        }
      }
    }
    return parametersMessage;
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

  static Set<String> getChilrenAllNamed(Base base) {
    final elements = <String>{};
    elements.addAll(base.allArgumentNames);
    elements
        .addAll(base.pages.expand((element) => getChilrenAllNamed(element)));
    return elements;
  }

  String? get groupKey {
    if (_groupKey != null) return _groupKey;
    return _groupKey = getGroupKey(firstUnique);
  }

  static const defaultKey = 'groupId';

  static String? getGroupKey(Base base) {
    if (base._groupKey != null) return base._groupKey!;
    final allmethod = getChilrenAllNamed(base);
    var name = defaultKey;
    while (true) {
      if (!allmethod.contains(name)) {
        return base._groupKey = name;
      }
      name = '$defaultKey${base.id}';
    }
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
