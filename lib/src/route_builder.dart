import 'dart:async';
import 'package:analyzer/dart/element/element.dart';

import 'package:nop_annotations/nop_annotations.dart';
import 'package:source_gen/source_gen.dart';
import 'package:build/build.dart';

import 'type_name.dart';

class RouteGenerator extends GeneratorForAnnotation<RouteMain> {
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
      for (var element in element.metadata) {
        final meta = element.computeConstantValue();
        final metaName = meta?.type?.getDisplayString(withNullability: false);
        if (isSameType<RouteMain>(metaName)) {
          return 'class Mae{}';
        }
      }
    }
  }
}

Builder routeMainBuilder(BuilderOptions options) =>
    SharedPartBuilder([RouteGenerator()], 'route_main');
