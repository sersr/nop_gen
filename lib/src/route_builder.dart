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

    return '''
    // ignore_for_file: prefer_const_constructors

    class $className {
      $buffer
      $bufferNav
    }
  ''';
  }

  void genRoute(
    Base base,
    List<RouteBuilderItemElement> builders,
    StringBuffer routes,
    StringBuffer routeNav, {
    String currentPath = '',
  }) {
    var children =
        base.pages.map((e) => getDartMemberName(e.realName)).toList();

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
        final baseChild = '$mainClassName($buffer)';
        final methods = <MethodElement>{};
        for (var item in builders) {
          if (item.pages.contains(classPage)) {
            methods.add(item.method);
          }
        }
        final builderBuffer = StringBuffer();
        if (methods.isNotEmpty) {
          final builds =
              methods.map((e) => '$targetClassName.${e.name}').toList();
          builderBuffer.write('''builders: const $builds,
        ''');
        }
        var childrenBuffer = '';
        if (children.isNotEmpty) {
          childrenBuffer = 'children: $children,';
        }
        routes.write('''
      static late final $name = NopRoute(
        name: '$routeName',
        fullName: '$fullName',
        $childrenBuffer
        builder: (context,arguments) =>
        Nop(
        $builderBuffer
        child: $baseChild,
        ), 
      );

      ''');
        final args = parametersNamedArgs.isEmpty
            ? 'const {}'
            : '{${parametersNamedArgs.join(',')}}';
        routeNav.write('''
    static NopRouteActionEntry<T> ${name}Nav<T>(
        {BuildContext? context, ${parametersPosOrNamed.join(',')}}) {
      return NopRouteActionEntry(
          context: context, route: $name, arguments: $args);
    }
    ''');
      }
    }
    for (var page in base.pages) {
      genRoute(page, builders, routes, routeNav, currentPath: fullName);
    }
  }

  NopMainElement gen(DartObject meta) {
    final className = meta.getField('className')?.toStringValue();
    final pages = meta.getField('pages')?.toListValue();
    final privite = meta.getField('privite')?.toBoolValue();
    final genKey = meta.getField('genKey')?.toBoolValue();
    final main = meta.getField('main')?.toTypeValue();
    final preInit = meta.getField('preInit')?.toListValue();
    final items = pages!.map(genItemElement).toList();
    final preInitElement =
        preInit!.map((e) => e.toTypeValue()!.element!).toList();

    return NopMainElement(
      className: className!,
      pages: items,
      main: main!.element!,
      preInit: preInitElement,
      privite: privite!,
      genKey: genKey!,
    );
  }

  RouteItemElement genItemElement(DartObject element) {
    final metaName = element.type?.getDisplayString(withNullability: false);
    assert(isSameType<RouteItem>(metaName));
    final name = element.getField('name')?.toStringValue();
    final page = element.getField('page')?.toTypeValue();
    final pages = element.getField('pages')?.toListValue();
    final preInit = element.getField('preInit')?.toListValue();
    final items = pages!.map(genItemElement).toList();
    final preInitElement =
        preInit!.map((e) => e.toTypeValue()!.element!).toList();
    return RouteItemElement(
        page: page!.element!,
        name: name!,
        pages: items,
        preInit: preInitElement);
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
    this.pages = const [],
    this.privite = true,
    this.genKey = false,
    required this.main,
    this.preInit = const [],
  });
  final String className;
  String get realClassName => className.isEmpty ? 'Routes' : className;
  @override
  String get name => 'root';

  @override
  bool get isRoot => true;
  final bool genKey;

  @override
  final List<RouteItemElement> pages;

  /// 除了root route其他都生成私有字段
  final bool privite;
  final Element main;
  @override
  Element get page => main;

  @override
  final List<Element> preInit;
}

class RouteItemElement with Base {
  const RouteItemElement({
    this.name = '',
    required this.page,
    this.pages = const [],
    this.preInit = const [],
  });
  @override
  final String name;

  /// 类型: Widget
  @override
  final Element page;

  @override
  final List<RouteItemElement> pages;

  @override
  final List<Element> preInit;
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

  List<Element> get preInit;
}

class RouteBuilderItemElement {
  const RouteBuilderItemElement({this.pages = const [], required this.method});
  final List<Element> pages;
  final MethodElement method;
}

Builder routeMainBuilder(BuilderOptions options) =>
    SharedPartBuilder([RouteGenerator()], 'route_main');
