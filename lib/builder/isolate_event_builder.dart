import 'dart:async';

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
  final parametersMessageList = <String>[];
  final parametersNamedUsed = <String>[];

  bool unique = false;
  bool cached = false;

  bool hasNamed = false;

  DartType? returnType;
  bool isDynamic = false;
  bool useTransferType = false;
  bool get useDynamic => isDynamic || (useTransferType && !useSameReturnType);
  bool useSameReturnType = false;
  String? _getReturnNameTransferType;

  String getReturnNameTransferType(LibraryReader reader) {
    if (_getReturnNameTransferType != null) return _getReturnNameTransferType!;
    var returnTypeName = '';
    final returnName = returnType.toString();
    void replace(String prefex) {
      returnName.replaceAllMapped(RegExp('^$prefex<(.*)>\$'), (match) {
        final item = match[1];
        final itemNotNull = '$item'.replaceAll('?', '');
        final currentItem = 'TransferType<$itemNotNull>';
        final itemElement = reader.findType(itemNotNull);

        if (itemElement is ClassElement) {
          useSameReturnType = itemElement.allSupertypes.any((element) => element
              .getDisplayString(withNullability: false)
              .contains(currentItem));
        }
        returnTypeName = useSameReturnType
            ? returnType.toString()
            : '$prefex<TransferType<$item>>';
        return '';
      });
    }

    replace('FutureOr');
    if (returnTypeName.isEmpty) {
      replace('Future');
    }
    if (returnTypeName.isEmpty) {
      replace('Stream');
    }

    return _getReturnNameTransferType =
        useTransferType && returnTypeName.isNotEmpty
            ? returnTypeName
            : isDynamic
                ? 'dynamic'
                : returnType.toString();
  }

  @override
  String toString() {
    return '$runtimeType: $returnType $name(${parameters.join(',')})';
  }
}

class IsolateEventGeneratorForAnnotation
    extends GeneratorForAnnotation<NopIsolateEvent> {
  late LibraryReader reader;
  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) async {
    reader = library;
    return super.generate(library, buildStep);
  }

  @override
  String generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    if (element is ClassElement) {
      final _root = gen(element);

      if (_root != null) return write(_root);
    }

    return '';
  }

  String lowName(String source) {
    return '${source[0].toLowerCase()}${source.substring(1)}';
  }

  String write(ClassItem item) {
    final buffer = StringBuffer();
    buffer.writeln('// ignore_for_file: annotate_overrides\n');
    buffer.write(writeMessageEnum(item, true));

    final className = item.className;
    final _allItems = <String>[];

    _allItems.addAll(item.sparateLists.expand((element) => getTypes(element)));
    if (item.methods.isNotEmpty) _allItems.addAll(getTypes(item));
    final _resolve = _allItems.map((e) => '${e}Resolve').join(',');

    final _name = rootResolveName == null || rootResolveName!.isEmpty
        ? className
        : rootResolveName;
    final mix = _resolve.isEmpty ? '' : ', $_resolve';
    buffer.writeln('''
        abstract class ${_name}ResolveMain extends $className with Resolve$mix {}''');
    //   @override
    //   bool resolve(resolveMessage){
    //     if (remove(resolveMessage)) return true;
    //     if (resolveMessage is! IsolateSendMessage  && resolveMessage is! KeyController) return false;
    //     return super.resolve(resolveMessage);
    //   }
    // }''');
    final _allItemsMessager = _allItems.map((e) => '${e}Messager').join(',');

    buffer.writeln(
        'abstract class ${_name}MessagerMain extends $className ${_allItemsMessager.isNotEmpty ? 'with' : ''} $_allItemsMessager{}');
    if (item.methods.isNotEmpty) buffer.write(writeItems(item));
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
    if (item.methods.where((element) => element.useDynamic).isNotEmpty) {
      _dynamicItems.add(item);
    }

    if (!item.separate) {
      _funcs.addAll(item.sparateLists.expand((e) {
        if (e.methods.where((element) => element.useDynamic).isNotEmpty) {
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
      if (element.methods.isNotEmpty) {
        final name = '${element.className}Dynamic';
        _implements.add(name);
        buffer.write('/// implements [${element.className}]\n');
        buffer.write('mixin $name {\n');
        element.methods.where((element) => element.useDynamic).forEach((e) {
          final name = e.getReturnNameTransferType(reader);
          buffer.write('$name ${e.name}Dynamic(${e.parameters.join(',')});');
        });
        buffer.write('}');
      }
    }
    if (_funcs.isNotEmpty) {
      final _impl =
          _implements.isEmpty ? '' : 'implements ${_implements.join(',')}';
      final _n = lowName(item.className!);
      final su = _supers.isEmpty ? item.className : _supers.join(',');
      buffer.write('mixin ${item.className}Resolve on Resolve, $su $_impl {\n');
      buffer
        ..write(
            'late final _${_n}ResolveFuncList = List<DynamicCallback>.unmodifiable(')
        ..write(
            '${List.generate(_funcs.length, (index) => '_${_funcs[index].name}_$index')}')
        ..writeln(');')
        ..writeln('''
        bool on${item.messagerType}Resolve(message) => false;
        @override
        bool resolve(resolveMessage) {
          if (resolveMessage is IsolateSendMessage) {
            final type = resolveMessage.type;
            if (type is  ${item.messagerType}Message) {
              dynamic result;
              try {
                if(on${item.messagerType}Resolve(resolveMessage)) return true;
                result = _${_n}ResolveFuncList.elementAt(type.index)(resolveMessage.args);
                receipt(result, resolveMessage);
              } catch (e) {
                receipt(result, resolveMessage, e);
              }
              return true; 
            }
          }
          return super.resolve(resolveMessage);
        }''');

      var count = 0;

      for (var f in _funcs) {
        final paras = f.parameters.length == 1 && !f.hasNamed
            ? 'args'
            : List.generate(f.parameters.length - f.parametersNamedUsed.length,
                (index) => 'args[$index]').join(',');
        final parasOp = f.parametersNamedUsed.join(',');
        final parasMes = paras.isNotEmpty
            ? parasOp.isNotEmpty
                ? ',$parasOp'
                : ''
            : parasOp;

        final name = f.getReturnNameTransferType(reader);
        final tranName = f.useDynamic ? '${f.name}Dynamic' : f.name;
        if (f.useTransferType) {
          buffer.writeln(
              '${f.returnType} ${f.name}(${f.parameters.join(',')}) => throw NopUseDynamicVersionExection("不要手动调用");');
        }
        buffer.write(
            '$name _${f.name}_$count(args) => $tranName($paras$parasMes);\n');
        count++;
      }
      buffer.writeln('\n}\n');
      var sendEvent = '${lowName(item.className!)}SendEvent';

      buffer.writeln('''
        /// implements [${item.className}]
        mixin ${item.className}Messager {
          SendEvent get sendEvent;
          SendEvent get $sendEvent => sendEvent;
        ''');

      for (var e in _funcs) {
        final returnType =
            (e.useTransferType || !e.isDynamic) ? e.returnType : 'dynamic';
        final tranName =
            (e.useTransferType || !e.isDynamic) ? e.name : '${e.name}Dynamic';

        buffer.write('$returnType $tranName(${e.parameters.join(',')})');
        final para = e.parametersMessageList.isEmpty
            ? 'null'
            : e.parametersMessageList.length == 1 && !e.hasNamed
                ? e.parametersMessageList.first
                : e.parametersMessageList;
        final eRetureType = e.returnType!;
        if (eRetureType.isDartAsyncFuture || eRetureType.isDartAsyncFutureOr) {
          buffer.write(
              ' {\n return $sendEvent.sendMessage(${item.messagerType}Message.${e.name},$para);');
        } else if (eRetureType.toString() == 'Stream' ||
            eRetureType.toString().startsWith('Stream<')) {
          final unique = e.unique;
          final cached = e.cached;
          var named = '';
          if (unique || cached) {
            final list = <String>[];
            if (unique) {
              list.add('unique: true');
            }
            if (cached) {
              list.add('cached: true');
            }
            named = ',${list.join(',')}';
          }
          buffer.write(
              '{\n return $sendEvent.sendMessageStream(${item.messagerType}Message.${e.name},$para$named);');
        } else {
          buffer.write('{\n');
        }
        buffer.write('\n}\n\n');
      }
      buffer.write('}\n\n');
    }

    return buffer.toString();
  }

  List<String> getTypes(ClassItem item) {
    final _list = <String>[];
    if (item.methods.isNotEmpty) {
      _list.add(item.className!);
    }
    if (item.separate) {
      _list.addAll(item.sparateLists.expand((e) => getTypes(e)));
    }
    return _list;
  }

  String writeMessageEnum(ClassItem item, [bool root = false]) {
    final buffer = StringBuffer();

    final _funcs = <String>[];
    _funcs.addAll(item.methods.map((e) => e.name!));
    if (root || item.separate) {
      buffer.writeAll(item.sparateLists.map((e) => writeMessageEnum(e)));
    } else {
      _funcs.addAll(
          item.sparateLists.expand((e) => e.methods.map((e) => e.name!)));
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
      method.returnType = methodElement.returnType;

      final parameters = <String>[];
      final parametersMessage = <String>[];
      final parametersPosOrNamed = <String>[];
      final parametersNamedUsed = <String>[];
      var count = -1;
      for (var item in methodElement.parameters) {
        count++;
        parametersMessage.add(item.name);
        final requiredValue = item.isRequiredNamed ? 'required ' : '';
        final defaultValue =
            item.hasDefaultValue ? ' = ${item.defaultValueCode}' : '';
        final fot = '$requiredValue${item.type} ${item.name}$defaultValue';

        if (item.isOptionalPositional) {
          parametersPosOrNamed.add(fot);
          continue;
        } else if (item.isNamed) {
          parametersPosOrNamed.add(fot);
          method.hasNamed = true;
          parametersNamedUsed.add('${item.name}: args[$count]');
          continue;
        }
        parameters.add(fot);
      }

      method.parameters.addAll(parameters);
      if (parametersPosOrNamed.isNotEmpty) {
        if (method.hasNamed) {
          method.parameters.add('{${parametersPosOrNamed.join(',')}}');
        } else {
          method.parameters.add('[${parametersPosOrNamed.join(',')}]');
        }
      }
      method.parametersMessageList.addAll(parametersMessage);
      method.parametersNamedUsed.addAll(parametersNamedUsed);

      methodElement.metadata.any((element) {
        final data = element.computeConstantValue();
        final type = data?.type?.getDisplayString(withNullability: false);
        if (type == 'NopIsolateMethod') {
          final _isDynamic =
              data?.getField('isDynamic')?.toBoolValue() ?? false;
          final _useTransferType =
              data?.getField('useTransferType')?.toBoolValue() ?? false;
          final _unique = data?.getField('unique')?.toBoolValue() ?? false;
          final _cached = data?.getField('cached')?.toBoolValue() ?? false;
          method
            ..isDynamic = _isDynamic
            ..useTransferType = _useTransferType
            ..unique = _unique
            ..cached = _cached;

          return true;
        }
        return false;
      });
      method.getReturnNameTransferType(reader);

      _item.methods.add(method);
    }
    return _item;
  }

  String? rootResolveName;
}

Builder isolateEventBuilder(BuilderOptions options) => SharedPartBuilder(
    [IsolateEventGeneratorForAnnotation()], 'nop_isolate_event');
