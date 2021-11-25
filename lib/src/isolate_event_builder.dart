import 'dart:async';

import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:nop_annotations/nop_annotations.dart';

import 'package:source_gen/source_gen.dart';
import 'package:analyzer/dart/element/element.dart';

class ClassItem {
  String? className;
  ClassItem? parent;

  final sparateLists = <ClassItem>[];
  bool separate = false;
  String messagerType = '';
  final methods = <Methods>[];
  String isolateName = '';
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
    if(source.isEmpty) return source;
    return '${source[0].toLowerCase()}${source.substring(1)}';
  }

  String upperName(String source) {
    if(source.isEmpty) return source;
    return '${source[0].toUpperCase()}${source.substring(1)}';
  }

  String write(ClassItem root) {
    final buffer = StringBuffer();
    buffer.writeln('// ignore_for_file: annotate_overrides\n');
    buffer.write(writeMessageEnum(root, true));

    final className = root.className;
    final _allItems = <String>[];

    _allItems.addAll(root.sparateLists.expand((element) => getTypes(element)));
    if (root.methods.isNotEmpty) _allItems.addAll(getTypes(root));
    final _resolve = _allItems.map((e) => '${e}Resolve').join(',');

    final _name = rootResolveName == null || rootResolveName!.isEmpty
        ? className
        : rootResolveName;
    final mix = _resolve.isEmpty ? '' : ', $_resolve';
    buffer.writeln('''
        abstract class ${_name}ResolveMain extends $className with Resolve$mix {}''');

    final _allItemsMessager = _allItems.map((e) => '${e}Messager').join(',');

    buffer.writeln(
        'abstract class ${_name}MessagerMain extends $className ${_allItemsMessager.isNotEmpty ? 'with' : ''} $_allItemsMessager{}');
    if (root.methods.isNotEmpty) buffer.write(writeItems(root));
    buffer.writeAll(root.sparateLists.map((e) => writeItems(e)));
    final multiItems = <String, Set<ClassItem>>{};

    String getNonDefaultName(ClassItem item) {
      if (item.isolateName.isEmpty) {
        if (item.parent != null) {
          return getNonDefaultName(item.parent!);
        }
        return 'default';
      }
      return item.isolateName;
    }

    void _add(ClassItem item) {
      item.isolateName = getNonDefaultName(item);

      final items =
          multiItems.putIfAbsent(item.isolateName, () => <ClassItem>{});
      items.add(item);

      for (var element in item.sparateLists) {
        _add(element);
      }
    }

    /// root 必须是`default`
    root.isolateName = 'default';
    _add(root);
    buffer
        .writeAll(multiItems.values.map((e) => writeMultiIsolate(e.toList())));
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

  /// 生成`Messager`、`Resolve`
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

    /// --------------- Mixin Dynamic ----------------------------
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

    /// ------------ Resolve -------------------------------------
    if (_funcs.isNotEmpty) {
      final _list = <String>[];

      final _n = lowName(item.className!);
      final su = _supers.isEmpty ? '${item.className}' : _supers.join(',');
      var impl = '';
      _list.add(su);
      if (_implements.isNotEmpty) {
        _list.add(_implements.join(','));
      }
      impl = _list.join(',');
      buffer.write(
          'mixin ${item.className}Resolve on Resolve implements $impl {\n');
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

      /// --------------------- Messager -----------------------
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

  String writeMultiIsolate(List<ClassItem> items) {
    if (items.isEmpty) {
      // ignore: avoid_print
      print('.------------error: ${items.length}');
      return '';
    }
    final buffer = StringBuffer();
    var isDefault = false;
    var isolateName = items.first.isolateName;
    if (isolateName == 'default') {
      isDefault = true;
      isolateName = '${items.first.className}Default';
    }

    /// ------- multi Isolate generator ----------
    // if (item.isolateName.isNotEmpty) {
    final allEnums = <String>{};

    void _fore(ClassItem innerItem) {
      if (innerItem.methods.isNotEmpty) {
        allEnums.add('${innerItem.messagerType}Message');
      }
      for (var element in innerItem.sparateLists) {
        if (element.isolateName.isEmpty || element.isolateName == isolateName) {
          _fore(element);
        }
      }
    }

    final _supers = <String>{};

    for (var item in items) {
      _fore(item);
      _supers.addAll(getSupers(item).whereType<String>());
    }

    final _list = <String>[];

    final su = _supers.isEmpty
        ? items.map((e) => e.className).join(',')
        : _supers.join(',');
    var impl = '';
    _list.add(su);
    // if (_implements.isNotEmpty) {
    //   _list.add(_implements.join(','));
    // }
    impl = _list.isNotEmpty ? ',${_list.join(',')}' : '';

    final upperIsolateName = upperName(isolateName);
    final lowIsolateName = lowName('${isolateName}Isolate');
    final sendPortOwner = '${lowIsolateName}SendPortOwner';
    var enums = '';
    if (allEnums.isNotEmpty) {
      final buffer = StringBuffer();
      buffer
        ..writeln('switch(messagerType.runtimeType){')
        ..writeAll(allEnums.map((e) => 'case $e:\n'))
        ..writeln('return $sendPortOwner;')
        ..writeln('default:')
        ..writeln('}');
      enums = buffer.toString();
    }
    final def = isDefault
        ? 'SendPortOwner? get defaultSendPortOwner => $sendPortOwner;'
            '  String get  defaultIsolateName => $lowIsolateName;'
        : '';
    buffer.writeln('''
        mixin Multi${upperIsolateName}Mixin on SendEvent,Send, SendMultiIsolateMixin $impl {
          Future<Isolate> createIsolate$upperIsolateName(SendPort remoteSendPort);
          final String $lowIsolateName = '$isolateName';
          $def
          SendPortOwner? $sendPortOwner;

          void createAllIsolate(SendPort remoteSendPort,add) {
            final task = createIsolate$upperIsolateName(remoteSendPort)
              .then((isolate)=> addNewIsolate($lowIsolateName,isolate));
            add(task);
            return super.createAllIsolate(remoteSendPort,add);
          }

          void onDoneMulti(String isolateName, SendPort localSendPort,SendPort remoteSendPort) {
            if(isolateName == $lowIsolateName) {
              $sendPortOwner = SendPortOwner(localSendPort: localSendPort, remoteSendPort: remoteSendPort);
              return;
            }
            super.onDoneMulti(isolateName,localSendPort,remoteSendPort);
          }

          void onResume() {
            if($sendPortOwner == null) {
              Log.e('sendPortOwner error: current $sendPortOwner == null',onlyDebug: false);
            }
            super.onResume();
          }

          SendPortOwner? getSendPortOwner(messagerType) {
            $enums
            if(messagerType == $lowIsolateName) {
              return $sendPortOwner;
            }
            return super.getSendPortOwner(messagerType);
          }

          void disposeIsolate(String isolateName) {
            if(isolateName == $lowIsolateName){
              $sendPortOwner = null;
              return;
            }
            return super.disposeIsolate(isolateName);
          }
        }

        mixin Multi${upperIsolateName}ResolveMixin on SendEvent,Send, ResolveMixin {
          bool add(message);
          SendPortOwner? $sendPortOwner;
          final String $lowIsolateName = '$isolateName';

          bool listenResolve(message) {
            // 处理返回的消息/数据
            if (add(message)) return true;
            // 默认，分发事件
            return super.listenResolve(message);
          }

          void onResolveReceivedSendPort(SendPortName sendPortName) {
            if (sendPortName.name == $lowIsolateName) {
              Log.w('received sendPort: \${sendPortName.name}', onlyDebug: false);
              $sendPortOwner = SendPortOwner(
                  localSendPort: sendPortName.sendPort, remoteSendPort: localSendPort);
              onResume();
              return;
            }
            super.onResolveReceivedSendPort(sendPortName);
          }

          FutureOr<bool> onClose() async {
            $sendPortOwner = null;
            return super.onClose();
          }
        }

        mixin Multi${upperIsolateName}OnResumeMixin on ResolveMixin {
           void onResumeResolve() {
              if (remoteSendPort != null) {
                remoteSendPort!.send(SendPortName('$isolateName',localSendPort));
              }
           }
        }

        ''');
    // }
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

  ClassItem? gen(ClassElement element, [ClassItem? parent]) {
    final _item = ClassItem();
    _item.parent = parent;

    bool generate = true;
    element.metadata.any((_e) {
      final meta = _e.computeConstantValue();
      final type = meta?.type?.getDisplayString(withNullability: false);
      if (type == 'NopIsolateEventItem') {
        final messageName = meta?.getField('messageName')?.toStringValue();
        final separate = meta?.getField('separate')?.toBoolValue();
        generate = meta?.getField('generate')?.toBoolValue() ?? generate;
        final isolateName = meta?.getField('isolateName')?.toStringValue();

        if (messageName != null && separate != null && isolateName != null) {
          _item.separate = separate;
          _item.isolateName = isolateName;
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

    _item.sparateLists.addAll(element.interfaces
        .map((e) => gen(e.element, _item))
        .whereType<ClassItem>());

    _item.sparateLists.addAll(element.mixins
        .map((e) => gen(e.element, _item))
        .whereType<ClassItem>());

    _item.className ??= element.name;
    if (_item.messagerType.isEmpty) {
      _item.messagerType = element.name;
    }

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
