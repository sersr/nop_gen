import 'dart:async';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import 'package:nop_annotations/nop_annotations.dart';
import 'package:nop_gen/nop_gen.dart';
import 'package:source_gen/source_gen.dart';
import 'package:build/build.dart';

import 'type_name.dart';

class RouteGenerator extends GeneratorForAnnotation<NopRouteMain> {
  late LibraryReader reader;
  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) {
    reader = library;
    return super.generate(library, buildStep);
  }

  @override
  generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    if (element is ClassElement) {
      for (var metaElement in element.metadata) {
        final meta = metaElement.computeConstantValue();
        final metaName = meta?.type?.getDisplayString(withNullability: false);
        if (isSameType<NopRouteMain>(metaName)) {
          final root = gen(meta!);
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
          main = root;
          return generator(root, map.values.toList());
        }
      }
    }
  }

  late String targetClassName;
  late NopMainElement main;

  String generator(
      NopMainElement root, List<RouteBuilderItemElement> builders) {
    final buffer = StringBuffer();
    final bufferNav = StringBuffer();
    genRoute(root, builders, buffer, bufferNav);
    var name = root.realClassName;

    final className = getDartClassName(name);
    final genBuffer = StringBuffer();
    genBuffer.write('// ignore_for_file: prefer_const_constructors\n\n');
    if (root.isSameClass) {
      genBuffer.write('''
    class $className {
      $buffer
      $bufferNav
    }
  ''');
    } else {
      final pathClassName = getDartClassName(root.realPathName);
      genBuffer.write('''
    class $className {
      $className._();
      $buffer
    }
  ''');
      genBuffer.write('''
    class $pathClassName {
      $pathClassName._();
      $bufferNav
    }
  ''');
    }
    return genBuffer.toString();
  }

  void genRoute(
    Base base,
    List<RouteBuilderItemElement> builders,
    StringBuffer routes,
    StringBuffer routeNav, {
    String currentPath = '',
  }) {
    final classPage = base.classElement;
    var mainClassName = classPage.name;

    var name = getDartMemberName(base.realName);
    var routeName = '/';
    var fullName = currentPath;
    if (base.isRoot) {
      routeName = '/';
      fullName = '/';
    } else {
      routeName = '/$name';
      if (fullName.endsWith('/')) {
        fullName += name;
      } else {
        fullName += routeName;
      }
    }

    for (var constructor in classPage.constructors) {
      if (constructor.name.isEmpty) {
        final isConst = constructor.isConst;
        final parameters = <String>[];
        final parametersMessage = <String>[];
        final parametersPosOrNamed = <String>[];
        final parametersNamedUsed = <String>[];
        final parametersNamedArgs = <String>[];
        for (var item in constructor.parameters) {
          if (!main.genKey && item.name == 'key') {
            continue;
          }
          parametersMessage.add(item.name);
          final requiredValue = item.isRequiredNamed ? 'required ' : '';
          final defaultValue =
              item.hasDefaultValue ? ' = ${item.defaultValueCode}' : '';
          final fot = '$requiredValue${item.type} ${item.name}$defaultValue';

          if (item.isOptionalPositional) {
            parametersPosOrNamed.add(fot);
            continue;
          } else if (item.isNamed) {
            parametersNamedUsed
                .add('${item.name}: arguments[\'${item.name}\']');
            parametersNamedArgs.add("'${item.name}': ${item.name}");
            parametersPosOrNamed.add(fot);
            continue;
          }
          parameters.add('arguments[\'${item.name}\']');
        }
        final buffer = StringBuffer();
        buffer.writeAll(parameters, ',');
        if (buffer.isNotEmpty) {
          buffer.write(',');
        }
        buffer.writeAll(parametersNamedUsed, ',');

        var baseChild = '$mainClassName($buffer)';

        final methods = <MethodElement>{};
        for (var item in builders) {
          if (item.pages.contains(classPage)) {
            methods.add(item.method);
          }
        }
        final preInitBuffer = StringBuffer();
        final hasPreInit =
            base.preInit.isNotEmpty || base.preInitUnique.isNotEmpty;
        final pageConst = buffer.isEmpty && isConst && !hasPreInit;

        if (hasPreInit) {
          preInitBuffer.write('preRun: (preInit) {');
        }
        for (var item in base.preInitUnique) {
          preInitBuffer.write('preInit<${item.name}>(shared: false);');
        }
        for (var item in base.preInit) {
          preInitBuffer.write('preInit<${item.name}>();');
        }
        if (preInitBuffer.isNotEmpty) {
          preInitBuffer.write('},');
        }

        var constPrefix = '';
        if (pageConst) {
          constPrefix = 'const';
        }

        final builderBuffer = StringBuffer();
        if (methods.isNotEmpty) {
          final builds =
              methods.map((e) => '$targetClassName.${e.name}').toList();
          if (pageConst) {
            builderBuffer.write('''builders: $builds,''');
          } else {
            builderBuffer.write('''builders: const $builds,''');
          }
        }

        var children = base.pages.map((e) {
          var memberName = getDartMemberName(e.realName);
          if (main.private) memberName = '_$memberName';

          return memberName;
        }).toList();

        var childrenBuffer = '';
        if (children.isNotEmpty) {
          childrenBuffer = 'children: $children,';
        }

        var memberName = name;
        if (!base.isRoot && main.private) {
          memberName = '_$name';
        }
        routes.write('''
      static final $memberName = NopRoute(
        name: '$routeName',
        fullName: '$fullName',
        $childrenBuffer
        builder: (context,arguments) =>
        $constPrefix Nop.page(
        $preInitBuffer
        $builderBuffer
        child: $baseChild,
        ), 
      );

      ''');
        final args = parametersNamedArgs.isEmpty
            ? 'const {}'
            : '{${parametersNamedArgs.join(',')}}';
        final funcName = main.funcName(name);
        final route = main.routeName(memberName);
        routeNav.write('''
    static NopRouteAction<T> $funcName<T>(
        {BuildContext? context, ${parametersPosOrNamed.join(',')}}) {
      return NopRouteAction(
          context: context, route: $route, arguments: $args);
    }
    ''');
      }
    }
    for (var page in base.pages) {
      genRoute(page, builders, routes, routeNav, currentPath: fullName);
    }
  }

  NopMainElement gen(DartObject value) {
    final className = value.getField('className')?.toStringValue();
    final rootName = value.getField('rootName')?.toStringValue();
    final pages = value.getField('pages')?.toListValue();
    final private = value.getField('private')?.toBoolValue();
    final genKey = value.getField('genKey')?.toBoolValue();
    final pathName = value.getField('pathName')?.toStringValue();
    final main = value.getField('main')?.toTypeValue();
    final items = pages!.map(genItemElement).toList();
    final preInit = value.getField('preInit')?.toListValue();
    final preInitElement =
        preInit!.map((e) => e.toTypeValue()!.element!).toSet();
    final preInitUnique = value.getField('preInitUnique')?.toListValue();
    final preInitUniqueElement =
        preInitUnique!.map((e) => e.toTypeValue()!.element!).toSet();

    return NopMainElement(
      className: className!,
      name: rootName!,
      pages: items,
      main: main!.element!,
      preInit: preInitElement,
      preInitUnique: preInitUniqueElement,
      private: private!,
      genKey: genKey!,
      pathName: pathName!,
    );
  }

  RouteItemElement genItemElement(DartObject value) {
    final metaName = value.type?.getDisplayString(withNullability: false);
    assert(isSameType<RouteItem>(metaName));
    final name = value.getField('name')?.toStringValue();
    final page = value.getField('page')?.toTypeValue();
    final pages = value.getField('pages')?.toListValue();
    final items = pages!.map(genItemElement).toList();
    final preInit = value.getField('preInit')?.toListValue();
    final preInitElement =
        preInit!.map((e) => e.toTypeValue()!.element!).toSet();
    final preInitUnique = value.getField('preInitUnique')?.toListValue();
    final preInitUniqueElement =
        preInitUnique!.map((e) => e.toTypeValue()!.element!).toSet();

    return RouteItemElement(
      page: page!.element!,
      name: name!,
      pages: items,
      preInit: preInitElement,
      preInitUnique: preInitUniqueElement,
    );
  }

  RouteBuilderItemElement genBuildElement(
      DartObject meta, MethodElement method) {
    final pages = meta.getField('pages')?.toListValue();
    final pagesElement = pages!.map((e) => e.toTypeValue()!.element!).toList();
    return RouteBuilderItemElement(pages: pagesElement, method: method);
  }
}

class NopMainElement with Base {
  const NopMainElement({
    this.className = '',
    this.name = 'root',
    this.pages = const [],
    this.private = true,
    this.genKey = false,
    this.pathName = '',
    required this.main,
    this.preInit = const {},
    this.preInitUnique = const {},
  });
  final String className;
  @override
  final String name;

  @override
  bool get isRoot => true;

  final bool genKey;
  final String pathName;

  bool get isSameClass => realPathName == realClassName;

  String get realClassName => className.isEmpty ? 'Routes' : className;

  String get realPathName => pathName.isEmpty ? 'NavRoutes' : pathName;

  String funcName(String name) {
    if (isSameClass) {
      return 'nav${getDartClassName(name)}';
    }
    return name;
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
  final Element main;
  @override
  Element get page => main;

  @override
  final Set<Element> preInit;
  @override
  final Set<Element> preInitUnique;
}

class RouteItemElement with Base {
  const RouteItemElement({
    this.name = '',
    required this.page,
    this.pages = const [],
    this.preInit = const {},
    this.preInitUnique = const {},
  });
  @override
  final String name;

  /// 类型: Widget
  @override
  final Element page;

  @override
  final List<RouteItemElement> pages;

  @override
  final Set<Element> preInit;
  @override
  final Set<Element> preInitUnique;
}

mixin Base {
  String get name;
  Element get page;
  ClassElement get classElement => page as ClassElement;
  bool get isRoot => false;
  String get fullName => '/';
  String get realName {
    if (name.isEmpty) {
      return classElement.name;
    }
    return name;
  }

  List<RouteItemElement> get pages;

  Set<Element> get preInit;
  Set<Element> get preInitUnique;
}

class RouteBuilderItemElement {
  const RouteBuilderItemElement({this.pages = const [], required this.method});
  final List<Element> pages;
  final MethodElement method;
}

Builder routeMainBuilder(BuilderOptions options) =>
    SharedPartBuilder([RouteGenerator()], 'route_main');
