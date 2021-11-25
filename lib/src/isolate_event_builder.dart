import 'dart:async';

import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:nop_annotations/nop_annotations.dart';

import 'package:source_gen/source_gen.dart';
import 'package:analyzer/dart/element/element.dart';

class ClassItem {
  String? className;
  ClassItem? parent;

  final supers = <ClassItem>[];
  bool separate = false;
  String messagerType = '';
  final methods = <Methods>[];
  String isolateName = '';
  List<String> connectToIsolate = const [];
  Set<String>? connects;

  @override
  String toString() {
    return '$runtimeType: $className, $messagerType,$separate <$supers>, $methods';
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
    if (source.isEmpty) return source;
    return '${source[0].toLowerCase()}${source.substring(1)}';
  }

  String upperName(String source) {
    if (source.isEmpty) return source;
    return '${source[0].toUpperCase()}${source.substring(1)}';
  }

  ClassItem? getNonDefaultName(ClassItem item) {
    if (item.isolateName.isEmpty) {
      if (item.parent != null) {
        return getNonDefaultName(item.parent!);
      }
      return null;
    }
    return item;
  }

  String write(ClassItem root) {
    /// root 必须是`default`
    if (root.isolateName.isEmpty) root.isolateName = '${root.className}Default';

    final buffer = StringBuffer();
    buffer.writeln('// ignore_for_file: annotate_overrides\n');
    buffer.write(writeMessageEnum(root, true));

    final className = root.className;

    final multiItems = <String, Set<ClassItem>>{};
    final _connectsMaps = <String, Set<String>>{};

    void _add(ClassItem item) {
      final parentItem = getNonDefaultName(item);
      if (parentItem != null && item != parentItem) {
        item.connectToIsolate = parentItem.connectToIsolate;
        item.isolateName = parentItem.isolateName;
      }

      final items =
          multiItems.putIfAbsent(item.isolateName, () => <ClassItem>{});
      items.add(item);
      final connects =
          _connectsMaps.putIfAbsent(item.isolateName, () => <String>{});
      item.connects = connects;
      final connectTo = item.connectToIsolate;
      for (var conTo in connectTo) {
        if (conTo == item.isolateName) continue;
        final connects = _connectsMaps.putIfAbsent(conTo, () => <String>{});
        connects.add(item.isolateName);
      }

      for (var element in item.supers) {
        _add(element);
      }
    }

    _add(root);
    final _allItems = <String>[];

    _allItems.addAll(root.supers.expand((element) => getTypes(element)));
    if (root.methods.isNotEmpty) _allItems.addAll(getTypes(root));
    final _resolve = _allItems.map((e) => '${e}Resolve').join(',');

    final _name = rootResolveName == null || rootResolveName!.isEmpty
        ? className
        : rootResolveName;
    final mix = _resolve.isEmpty ? '' : ', $_resolve';
    var _allItemsMessager = _allItems.map((e) => '${e}Messager').join(',');
    _allItemsMessager =
        _allItemsMessager.isNotEmpty ? 'SendEvent,$_allItemsMessager' : '';
    buffer
      ..writeln('''
        abstract class ${_name}ResolveMain extends $className with Resolve$mix {}''')
      ..writeln(
          'abstract class ${_name}MessagerMain extends $className  ${_allItemsMessager.isNotEmpty ? 'with' : ''} $_allItemsMessager{}')
      ..write(writeItems(root, true))
      ..writeAll(multiItems.values.map((e) => writeMultiIsolate(e.toList())));

    return buffer.toString();
  }

  List<Methods> getMethods(ClassItem item) {
    final _methods = <Methods>[];
    _methods.addAll(item.methods);
    if (!item.separate) {
      _methods.addAll(item.supers.expand((e) => getMethods(e)));
    }
    return _methods;
  }

  List<String?> getSupers(ClassItem item) {
    final _supers = <String?>[];
    _supers.add(item.className);
    if (!item.separate) {
      _supers.addAll(item.supers.expand((e) => getSupers(e)));
    }
    return _supers;
  }

  /// 生成`Messager`、`Resolve`
  String writeItems(ClassItem item, [bool root = false]) {
    final buffer = StringBuffer();
    final _funcs = <Methods>[];
    _funcs.addAll(item.methods);
    final _supers = <String>[];
    final _dynamicItems = <ClassItem>{};
    if (item.methods.where((element) => element.useDynamic).isNotEmpty) {
      _dynamicItems.add(item);
    }

    if (item.separate || root) {
      buffer.writeAll(item.supers.map((e) => writeItems(e)));
    } else {
      _funcs.addAll(item.supers.expand((e) {
        if (e.methods.where((element) => element.useDynamic).isNotEmpty) {
          _dynamicItems.add(e);
        }
        return getMethods(e);
      }));
      _supers.addAll(getSupers(item).whereType<String>());
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
        mixin ${item.className}Messager on SendEvent {
          SendEvent get sendEvent;
          SendEvent get $sendEvent => sendEvent;
        ''');
      buffer.writeln('''
        Iterable<Type>? getProtocols(String name) sync*{
          if(name == '${lowName(item.isolateName)}'){
            yield ${item.messagerType}Message;
          }
            final prots = super.getProtocols(name);
            if (prots != null) {
              yield* prots;
            }
        }
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

    /// ------- multi Isolate generator ----------
    // if (item.isolateName.isNotEmpty) {
    final allEnums = <String>{};
    final _supers = <String>{};

    void _fore(ClassItem innerItem) {
      if (innerItem.methods.isNotEmpty) {
        _supers.add(innerItem.messagerType);

        allEnums.add('${innerItem.messagerType}Message');
      }
      for (var element in innerItem.supers) {
        if (element.isolateName == isolateName) {
          _fore(element);
        }
      }
    }

    for (var item in items) {
      _fore(item);
    }

    final su = _supers.join(',');
    // ? items.map((e) => e.className).join(',')
    // : _supers.join(',');
    var impl = '';

    impl = su.isNotEmpty ? ',$su' : '';

    if (isolateName.toLowerCase().contains('default')) {
      isDefault = true;
      // isolateName = '${items.first.className}Default';
    }

    final upperIsolateName = upperName(isolateName);
    final lowIsolateName = lowName(isolateName);
    final lowIsolateNameIsolate = '${lowIsolateName}Isolate';
    final sendPortOwner = '${lowIsolateNameIsolate}SendPortOwner';
    var enums = '';
    var protocols = '';
    if (allEnums.isNotEmpty) {
      final buffer = StringBuffer();
      final pbuffer = StringBuffer();
      pbuffer
        ..write('[')
        ..write(allEnums.join(','))
        ..write(',]');
      buffer
        ..writeln('switch(messagerType.runtimeType){')
        ..writeAll(allEnums.map((e) => 'case $e:\n'))
        ..writeln('return $sendPortOwner;')
        ..writeln('default:')
        ..writeln('}');
      enums = buffer.toString();
      protocols = pbuffer.toString();
    }
    final isolateProtocols = '${lowIsolateName}Protocols';
    var connectIsolate = '';
    var connectIsolateAllOwners = '';
    var connects = '';
    final connectName = '${isolateName}Connects';
    var connectToList = '';
    var protCase = '';
    if (items.first.connectToIsolate.isNotEmpty) {
      final buffer = StringBuffer();
      final cbuffer = StringBuffer();

      for (var item in items.first.connectToIsolate) {
        final itemLow = lowName(item);
        final itemProt = '${itemLow}Protocols';
        final itemOwner = '${itemLow}IsolateSendPortOwner';

        cbuffer.write(
            'SendPortOwner? get $itemOwner;\n List<Type> get $itemProt;');
        buffer.writeln(' $sendPortOwner!.localSendPort.send(SendPortName('
            '\'$item\', $itemOwner!.localSendPort,protocols: $itemProt));');
      }

      connectToList =
          'final ${lowIsolateName}ConnectId = \'${lowIsolateName}_connect\';';
      connectIsolate = buffer.toString();
      connectIsolateAllOwners = cbuffer.toString();
    }

    protCase = items.first.connectToIsolate
        .map((e) => 'prots!.every((e)=> ${lowName(e)}Protocols.contains(e))')
        .join('||');
    if (protCase.isNotEmpty) {
      protCase = '''
      if($protCase) {
        Log.i('all prots matched', onlyDebug: false);
      }else {
        Log.w('not matched \$prots',onlyDebug: false);
      }
        ''';
    }
    var onDoneConnect = '';

    //  items.first.connectToIsolate.isEmpty
    //     ? ''
    //     : '''
    //   else if( ${lowIsolateName}ConnectId == sendPortName.name) {
    //     final prots = sendPortName.protocols;
    //     if(prots?.isNotEmpty == true) {
    //       $protCase
    //     }
    //     Log.i('local: remote connected, \${sendPortName.name}',onlyDebug: false);
    //     return;
    //   }
    //  ''';

    if (items.first.connects?.isNotEmpty == true) {
      final buffer = StringBuffer();
      buffer
        ..write('[\'')
        ..writeAll(items.first.connects!.map((e) => lowName(e)), '\',\'')
        ..write('\']');
      connects = buffer.toString();
    }
    var connectNames = '';
    var connectRecieive = '';
    final connectTos = items.first.connectToIsolate;
    if (connectTos.isNotEmpty) {
      var conts = '';
      if (connects.isNotEmpty) {
        connectNames = 'final $connectName = $connects;';
        conts = '''
      for (var item in $connectName) {
            if(sendPortName.name == item) {
                  final prots = getProtocols($lowIsolateNameIsolate)?.toList();
                remoteSendPort!.send(SendPortName('\${item}_connect',localSendPort,protocols: prots,));
              return;
            }
          }

      ''';
      }
      var ctos = '';
      var onClose = '';
      if (connectTos.isNotEmpty) {
        final buffer = StringBuffer();
        buffer.writeAll(connectTos
            .map((e) => 'SendPortOwner? ${lowName(e)}IsolateSendPortOwner;\n'));

        connectNames = '$connectNames\n $buffer';
        final cases = connectTos.map((e) => '''
        case '$e':
          ${lowName(e)}IsolateSendPortOwner =SendPortOwner(
              localSendPort: sendPortName.sendPort, remoteSendPort: localSendPort,);
              final localProts = sendPortName.protocols;
              final prots = getProtocols('${lowName(e)}')?.toList();
            // remoteSendPort!.send(SendPortName('${lowIsolateName}_connect',localSendPort,protocols: prots,));
              if(localProts != null && prots != null) {
                if(prots.every((e) => localProts.contains(e))) {
                  Log.w('remote: received ${lowName(e)}, prots: matched',onlyDebug:false);
                }else{
                  Log.w('remote: not metched, local:\$localProts, remote: \$prots',onlyDebug: false);
                }
              }
            return;
        ''').join();

        ctos = '''
        switch(sendPortName.name) {
          $cases
          default:
        }
        ''';
        onClose = connectTos
            .map((e) => '${lowName(e)}IsolateSendPortOwner = null;')
            .join('\n');
        onClose = '''
          FutureOr<bool> onClose() async {
            $onClose
            return super.onClose();
          }
        ''';
      }

      connectRecieive = '''
        Iterable<Type>? getProtocols(String name);
        void onResolveReceivedSendPort(SendPortName sendPortName) {
          $conts
          $ctos
        
          super.onResolveReceivedSendPort(sendPortName);
        }

        $onClose
        ''';
    }

    final createIsolate =
        'Future<Isolate> createIsolate$upperIsolateName(SendPort remoteSendPort);';
    final createIsolateAll = '''
      void createAllIsolate(SendPort remoteSendPort,add) {
            final task = createIsolate$upperIsolateName(remoteSendPort)
              .then((isolate)=> addNewIsolate($lowIsolateNameIsolate,isolate));
            add(task);
            return super.createAllIsolate(remoteSendPort,add);
          }
          ''';
    final onResume = '''
          void onResume() {
            if($sendPortOwner == null) {
              Log.e('sendPortOwner error: current $sendPortOwner == null',onlyDebug: false);
            }

            $connectIsolate

            super.onResume();
          }
    
          ''';
    final onDoneMuti = '''
    if(sendPortName.name == $lowIsolateNameIsolate) {
      final equal = iterableEquality.equals(sendPortName.protocols,  $isolateProtocols);

      $sendPortOwner = SendPortOwner(localSendPort: sendPortName.sendPort,
        remoteSendPort: remoteSendPort,);
      Log.i('init: protocols equal: \$equal | \$$lowIsolateNameIsolate', onlyDebug: false);
      return;
    }
    
    ''';

    final mesageTypes = items
        .where((element) => element.methods.isNotEmpty)
        .map((e) => 'case ${e.messagerType}Message:')
        .join('\n');

    final getSendPortOwner = '''
            SendPortOwner? getSendPortOwner(key) {
              switch(key.runtimeType) {
                $mesageTypes
                return ${lowIsolateName}IsolateSendPortOwner;
                default:
              }
          return super.getSendPortOwner(key);
        }
    
    ''';
    final def = isDefault
        ? 'SendPortOwner? get defaultSendPortOwner => $sendPortOwner;'
            '  String get  defaultIsolateName => $lowIsolateNameIsolate;'
        : '';
    buffer.writeln('''
        mixin Multi${upperIsolateName}Mixin on SendEvent,Send, SendMultiIsolateMixin $impl {
          final String $lowIsolateNameIsolate = '$isolateName';
          $def
          SendPortOwner? $sendPortOwner;

          final $isolateProtocols = $protocols;

          $connectToList

          $connectIsolateAllOwners

          $createIsolate

          $createIsolateAll

          void onDoneMulti(SendPortName sendPortName, SendPort remoteSendPort) {
            $onDoneMuti$onDoneConnect

            super.onDoneMulti(sendPortName, remoteSendPort);
          }
          
          $onResume

          SendPortOwner? getSendPortOwner(messagerType) {
            $enums
            if(messagerType == $lowIsolateNameIsolate) {
              return $sendPortOwner;
            }
            return super.getSendPortOwner(messagerType);
          }

          void disposeIsolate(String isolateName) {
            if(isolateName == $lowIsolateNameIsolate){
              $sendPortOwner = null;
              return;
            }
            return super.disposeIsolate(isolateName);
          }
        }

        /// 在[Resolve]中为`Messager`提供便携
        mixin Multi${upperIsolateName}ResolveMixin on Send, ResolveMixin {
          bool add(message);

          final String $lowIsolateNameIsolate = '$isolateName';
          $connectNames
          $connectRecieive

          bool listenResolve(message) {
            if (add(message)) return true;
            return super.listenResolve(message);
          }
        }

        mixin Multi${upperIsolateName}OwnerMixin on SendEvent {
        SendPortOwner? get $sendPortOwner;
          $getSendPortOwner
        }

        mixin Multi${upperIsolateName}OnResumeMixin on ResolveMixin $impl {
           void onResumeResolve() {
              if (remoteSendPort != null) {
                remoteSendPort!.send(SendPortName('$isolateName',localSendPort,protocols: $protocols,));
              }
              super.onResumeResolve();
           }
        }



        ''');

    return buffer.toString();
  }

  List<String> getTypes(ClassItem item) {
    final _list = <String>[];
    if (item.methods.isNotEmpty) {
      _list.add(item.className!);
    }
    if (item.separate) {
      _list.addAll(item.supers.expand((e) => getTypes(e)));
    }
    return _list;
  }

  String writeMessageEnum(ClassItem item, [bool root = false]) {
    final buffer = StringBuffer();

    final _funcs = <String>[];
    _funcs.addAll(item.methods.map((e) => e.name!));
    if (root || item.separate) {
      buffer.writeAll(item.supers.map((e) => writeMessageEnum(e)));
    } else {
      _funcs.addAll(item.supers.expand((e) => e.methods.map((e) => e.name!)));
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
        final connectToIsolate =
            meta?.getField('connectToIsolate')?.toListValue();
        // final create = meta?.getField('create')?.toBoolValue();

        if (messageName != null &&
            separate != null &&
            isolateName != null &&
            connectToIsolate != null) {
          _item.separate = separate;
          _item.isolateName = isolateName;
          if ((parent == null || _item.isolateName.isNotEmpty) &&
              connectToIsolate.isNotEmpty) {
            _item.connectToIsolate = connectToIsolate
                .map((e) => e.toStringValue())
                .whereType<String>()
                .toList();
          }

          if (messageName.isNotEmpty) _item.messagerType = messageName;
          return true;
        }
      } else if (type == 'NopIsolateEvent') {
        rootResolveName = meta?.getField('resolveName')?.toStringValue();
      }
      return false;
    });

    if (!generate) return null;

    final _ci = genSuperType(element);
    if (_ci != null) _item.supers.add(_ci);

    _item.supers.addAll(element.interfaces
        .map((e) => gen(e.element, _item))
        .whereType<ClassItem>());

    _item.supers.addAll(element.mixins
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
