import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:nop_annotations/nop_annotations.dart';

import 'package:source_gen/source_gen.dart';
import 'package:analyzer/dart/element/element.dart';

class ClassItem {
  String? className;
  final sparateLists = <ClassItem>[];
  bool separate = false;
  String? messagerType;
  final methods = <Methods>[];
  @override
  String toString() {
    return '$runtimeType: $className, $messagerType,$separate <$sparateLists>, $methods';
  }
}

class Methods {
  String? name;
  final parameters = <String>[];
  DartType? returnType;
  bool isDynamic = false;
  @override
  String toString() {
    return '$runtimeType: $returnType $name(${parameters.join(',')})';
  }
}

class IsolateEventGeneratorForAnnotation
    extends GeneratorForAnnotation<NopIsolateEvent> {
  @override
  String generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    if (element is ClassElement) {
      final _root = gen(element);

      if (_root != null) return write(_root);
    }

    return '';
  }

  final _override = '\n@override\n';

  String write(ClassItem item) {
    final buffer = StringBuffer();
    buffer.writeAll(item.sparateLists.map((e) => writeMessageEnum(e)));
    final className = item.className;
    final _allItems = <String>[];
    // _allItems.addAll(item.sparateLists.map((e) => e.className!));
    _allItems.addAll(item.sparateLists.expand((element) => getTypes(element)));

    final _resolve = _allItems.map((e) => '${e}Resolve').join(',');
    // item.sparateLists.map((e) => '${e.className}Resolve').join(',');
    final _name = rootResolveName == null || rootResolveName!.isEmpty
        ? className
        : rootResolveName;
    buffer
      ..write('abstract class ${_name}Resolve extends $className with Resolve')
      ..write(_resolve.isEmpty ? '' : ', $_resolve')
      ..write('{\n')
      ..write(_override)
      ..write('bool resolve(resolveMessage){\n')
      ..write('if (remove(resolveMessage)) return true;\n')
      ..write(' if (resolveMessage is! IsolateSendMessage) return false;\n')
      ..write('return super.resolve(resolveMessage);\n')
      ..write('\n}\n}\n');
    final _allItemsMessager = _allItems.map((e) => '${e}Messager').join(',');

    buffer
      ..write(
          'abstract class ${_name}Messager extends $className ${_allItemsMessager.isNotEmpty ? 'with' : ''} ')
      ..write(_allItemsMessager)
      ..write('{\n')
      ..write('}\n\n');
    buffer.writeAll(item.sparateLists.map((e) => writeItems(e)));
    return buffer.toString();
  }

  List<Methods> getMethods(ClassItem item) {
    final _methods = <Methods>[];
    _methods.addAll(item.methods);
    if (!item.separate) {
      _methods.addAll(item.sparateLists.expand((e) => getMethods(e)));
    }
    return _methods;
  }

  List<String?> getSupers(ClassItem item) {
    final _supers = <String?>[];
    _supers.add(item.className);
    if (!item.separate) {
      _supers.addAll(item.sparateLists.expand((e) => getSupers(e)));
    }
    return _supers;
  }

  String writeItems(ClassItem item) {
    final buffer = StringBuffer();
    final _funcs = <Methods>[];
    _funcs.addAll(item.methods);
    final _supers = <String>[];
    final _dynamicItems = <ClassItem>{};
    if (item.methods.where((element) => element.isDynamic).isNotEmpty) {
      _dynamicItems.add(item);
    }

    if (!item.separate) {
      _funcs.addAll(item.sparateLists.expand((e) {
        if (e.methods.where((element) => element.isDynamic).isNotEmpty) {
          _dynamicItems.add(e);
        }
        return getMethods(e);
      }));
      _supers.addAll(getSupers(item).whereType<String>());
    } else {
      buffer.writeAll(item.sparateLists.map((e) => writeItems(e)));
    }
    final _implements = <String>[];
    for (var element in _dynamicItems) {
      final name = '${element.className}Dynamic';
      _implements.add(name);
      buffer.write('abstract class $name implements ${element.className}{\n');
      element.methods.where((element) => element.isDynamic).forEach((e) {
        buffer.write('dynamic ${e.name}Dynamic(${e.parameters.join(',')});');
      });
      buffer.write('}');
    }
    final _impl =
        _implements.isEmpty ? '' : 'implements ${_implements.join(',')}';
    final _n =
        '${item.className?[0].toLowerCase()}${item.className?.substring(1)}';
    final su = _supers.isEmpty ? item.className : _supers.join(',');
    buffer.write('mixin ${item.className}Resolve on Resolve, $su $_impl {\n');
    if (item.methods.isNotEmpty) {
      buffer
        ..write(
            'late final _${_n}ResolveFuncList = List<DynamicCallback>.unmodifiable(')
        ..write(
            '${List.generate(_funcs.length, (index) => '_${_funcs[index].name}_$index')}')
        ..write(');\n')
        ..write(_override)
        ..write('  bool resolve(resolveMessage) {\n')
        ..write('if (resolveMessage is IsolateSendMessage) {\n')
        ..write('final type = resolveMessage.type; \n')
        ..write('if (type is  ${item.messagerType}Message) {\n')
        ..write('dynamic result;\n')
        ..write('try {\n')
        ..write(
            'result = _${_n}ResolveFuncList.elementAt(type.index)(resolveMessage.args);\n')
        ..write('send(result, resolveMessage);\n')
        ..write('} catch (e) {\n')
        ..write('send(result, resolveMessage, e);\n}')
        ..write('return true;\n}');

      buffer.write('}\n');
      buffer.write('return super.resolve(resolveMessage);\n}');
      var count = 0;

      for (var f in _funcs) {
        final paras = f.parameters.length == 1
            ? 'args'
            : List.generate(f.parameters.length, (index) => 'args[$index]')
                .join(',');
        final name = f.isDynamic ? 'dynamic' : f.returnType;
        final tranName = f.isDynamic ? '${f.name}Dynamic' : f.name;
        buffer.write('$name _${f.name}_$count(args) => $tranName($paras);\n');
        // if (f.isDynamic)
        //   buffer.write('dynamic $tranName(${f.parameters.join(',')});\n');
        count++;
      }
    }
    buffer.write('\n}\n\n');

    buffer.write(
        'mixin ${item.className}Messager implements ${item.className} {\n');

    if (item.methods.isNotEmpty) buffer.write('SendEvent get send;\n\n');

    for (var e in _funcs) {
      final returnType = e.isDynamic ? 'dynamic' : e.returnType;
      final tranName = e.isDynamic ? '${e.name}Dynamic' : e.name;

      buffer
        ..write(e.isDynamic ? '' : _override)
        ..write('$returnType $tranName(${e.parameters.join(',')})');
      final para = e.parameters.isEmpty
          ? 'null'
          : e.parameters.length == 1
              ? e.parameters.first.split(' ')[1]
              : e.parameters.map((e) => e.split(' ')[1]).toList();
      if (e.returnType!.isDartAsyncFuture ||
          e.returnType!.isDartAsyncFutureOr) {
        buffer.write(
            'async {\n return send.sendMessage(${item.messagerType}Message.${e.name},$para);');
      } else if (e.returnType!.toString().startsWith('Stream')) {
        buffer.write(
            '{\n return send.sendMessageStream(${item.messagerType}Message.${e.name},$para);');
      } else {
        buffer.write('{\n');
      }
      buffer.write('\n}\n\n');
    }

    buffer.write('}\n\n');
    return buffer.toString();
  }

  List<String> getTypes(ClassItem item) {
    final _list = <String>[];

    _list.add(item.className!);
    if (item.separate) {
      _list.addAll(item.sparateLists.expand((e) => getTypes(e)));
    }
    return _list;
  }

  String writeMessageEnum(ClassItem item) {
    final buffer = StringBuffer();

    final _funcs = <String>[];
    _funcs.addAll(item.methods.map((e) => e.name!));
    if (!item.separate) {
      _funcs.addAll(
          item.sparateLists.expand((e) => e.methods.map((e) => e.name!)));
    } else {
      buffer.writeAll(item.sparateLists.map((e) => writeMessageEnum(e)));
    }
    if (_funcs.isNotEmpty) {
      buffer
        ..write('enum ${item.messagerType}Message {\n')
        ..write(_funcs.join(','))
        ..write('\n}\n');
    }
    return buffer.toString();
  }

  ClassItem? genSuperType(ClassElement element) {
    if (element.supertype != null &&
        element.supertype!.getDisplayString(withNullability: false) !=
            'Object') {
      return gen(element.supertype!.element);
    }
  }

  ClassItem? gen(ClassElement element) {
    final _item = ClassItem();

    bool generate = true;
    element.metadata.any((_e) {
      final meta = _e.computeConstantValue();
      final type = meta?.type?.getDisplayString(withNullability: false);
      if (type == 'NopIsolateEventItem') {
        final messageName = meta?.getField('messageName')?.toStringValue();
        final separate = meta?.getField('separate')?.toBoolValue();
        generate = meta?.getField('generate')?.toBoolValue() ?? generate;

        if (messageName != null && separate != null) {
          _item.separate = separate;
          if (messageName.isNotEmpty) _item.messagerType = messageName;
          return true;
        }
      } else if (type == 'NopIsolateEvent') {
        rootResolveName = meta?.getField('resolveName')?.toStringValue();

        return true;
      }
      return false;
    });
    if (!generate) return null;

    final _ci = genSuperType(element);
    if (_ci != null) _item.sparateLists.add(_ci);

    _item.sparateLists.addAll(
        element.interfaces.map((e) => gen(e.element)).whereType<ClassItem>());
    _item.sparateLists.addAll(
        element.mixins.map((e) => gen(e.element)).whereType<ClassItem>());

    _item.className ??= element.name;
    _item.messagerType ??= element.name;

    for (var methodElement in element.methods) {
      final method = Methods();

      method.name = methodElement.name;
      method.returnType = methodElement.type.returnType;

      method.parameters
          .addAll(methodElement.parameters.map((e) => '${e.type} ${e.name}'));

      methodElement.metadata.any((element) {
        final data = element.computeConstantValue();
        final type = data?.type?.getDisplayString(withNullability: false);
        if (type == 'NopIsolateMethod') {
          final _isDynamic =
              data?.getField('isDynamic')?.toBoolValue() ?? false;
          method.isDynamic = _isDynamic;
          return true;
        }
        return false;
      });

      _item.methods.add(method);
    }
    return _item;
  }

  String? rootResolveName;
}

Builder isolateEventBuilder(BuilderOptions options) => SharedPartBuilder(
    [IsolateEventGeneratorForAnnotation()], 'nop_isolate_event');
