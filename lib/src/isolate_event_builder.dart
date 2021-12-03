import 'dart:async';

import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:nop_annotations/nop_annotations.dart';

import 'package:source_gen/source_gen.dart';
import 'package:analyzer/dart/element/element.dart';

class IsolateGroup {
  IsolateGroup(this.isolateName);
  final String isolateName;
  final connectToGroup = <IsolateGroup>{};

  /// 要连接此`isolateName`Isolate
  /// `connects`可能拥有相同的`isolate`
  final Set<ClassItem> connects = {};

  /// 当前`isolateName`支持的协议
  final Set<ClassItem> currentItems = {};
  void addConnectToGroup(IsolateGroup group) {
    connectToGroup.add(group);
  }

  void addConnect(ClassItem item) {
    connects.add(item);
  }

  void addCurerntItem(ClassItem item) {
    currentItems.add(item);
  }
}

class ClassItem {
  String? className;
  ClassItem? parent;

  final supers = <ClassItem>[];
  bool separate = false;
  String messagerType = '';
  final methods = <Methods>[];
  String isolateName = '';
  List<String> connectToIsolate = const [];
  List<ClassItem> privateProtocols = const [];
  @override
  String toString() {
    return '$runtimeType: $className';
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
    buffer.writeln('// ignore_for_file: annotate_overrides\n'
        '// ignore_for_file: curly_braces_in_flow_control_structures');
    buffer.write(writeMessageEnum(root, true));

    final className = root.className;

    final multiItems = <String, IsolateGroup>{};

    void _add(ClassItem item) {
      final parentItem = getNonDefaultName(item);
      if (parentItem != null && item != parentItem) {
        item.connectToIsolate = parentItem.connectToIsolate;
        item.isolateName = parentItem.isolateName;
      }
      for (var element in item.privateProtocols) {
        element.isolateName = item.isolateName;
        element.connectToIsolate = item.connectToIsolate;
      }

      final group = multiItems.putIfAbsent(
          item.isolateName, () => IsolateGroup(item.isolateName));
      group.addCurerntItem(item);
      item.privateProtocols.forEach(group.addCurerntItem);
      final connectTo = item.connectToIsolate;
      for (var connectToIsolateName in connectTo) {
        if (connectToIsolateName == item.isolateName) continue;
        final other = multiItems.putIfAbsent(
            connectToIsolateName, () => IsolateGroup(connectToIsolateName));
        other.addConnect(item);
        group.addConnectToGroup(other);
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
        abstract class ${_name}ResolveMain extends $className with ListenMixin, Resolve$mix {}''')
      ..writeln(
          'abstract class ${_name}MessagerMain extends $className  ${_allItemsMessager.isNotEmpty ? 'with' : ''} $_allItemsMessager{}')
      ..write(writeItems(root, true))
      ..writeAll(multiItems.values.map((e) => writeMultiIsolate(e)));

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
    if (item.privateProtocols.isNotEmpty) {
      buffer.writeAll(item.privateProtocols.map((e) => writeItems(e)));
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
      var sendEvent = 'sendEvent';

      /// --------------------- Messager -----------------------\
      final lowIsolateName = lowName(item.isolateName);
      buffer.write('''
        /// implements [${item.className}]
        mixin ${item.className}Messager on SendEvent {
          SendEvent get sendEvent;''');
      buffer.write('''
        String get $lowIsolateName => '$lowIsolateName';
        Iterable<Type> getProtocols(String name) sync*{
          if(name == $lowIsolateName)
            yield ${item.messagerType}Message;
          yield* super.getProtocols(name);
        }''');
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
              ' {return $sendEvent.sendMessage(${item.messagerType}Message.${e.name},$para,isolateName:$lowIsolateName);');
        } else if (eRetureType.toString() == 'Stream' ||
            eRetureType.toString().startsWith('Stream<')) {
          final unique = e.unique;
          final cached = e.cached;
          var named = '';

          final list = <String>[];
          if (unique) {
            list.add('unique: true');
          }
          if (cached) {
            list.add('cached: true');
          }
          list.add('isolateName: $lowIsolateName');
          named = ',${list.join(',')}';
          buffer.write(
              '{return $sendEvent.sendMessageStream(${item.messagerType}Message.${e.name},$para$named);');
        } else {
          buffer.write('{');
        }
        buffer.write('}');
      }
      buffer.write('}');
    }

    return buffer.toString();
  }

  /// ------- multi Isolate generator ----------
  /// 生成多个[Isolate]mixins
  /// 初始化时检测协议匹配
  /// 子隔离之间通信实现，连接时检测协议
  String writeMultiIsolate(IsolateGroup group) {
    List<ClassItem> items = group.currentItems.toList();
    if (items.isEmpty) {
      // ignore: avoid_print
      print('.------------error: ${items.length}');
      return '';
    }
    var isolateName = group.isolateName;
    final upperIsolateName = upperName(isolateName);
    final lowIsolateName = lowName(isolateName);
    final allConnectToIsolate = group.connectToGroup;

    final buffer = StringBuffer();

    var isDefault = group.isolateName.toLowerCase().contains('default');

    final genEnums = <String>{};
    final genSupers = <String>{};
    void clear() {
      genEnums.clear();
      genSupers.clear();
    }

    void getProtocolTypesAndSupers(ClassItem innerItem) {
      if (innerItem.methods.isNotEmpty) {
        genSupers.add(innerItem.className!);

        genEnums.add('${innerItem.messagerType}Message');
        for (var item in innerItem.privateProtocols) {
          getProtocolTypesAndSupers(item);
        }
      }
      for (var element in innerItem.supers) {
        if (element.isolateName == isolateName) {
          getProtocolTypesAndSupers(element);
        }
      }
    }

    // 获取[method]非空的所有协议[enum],
    for (var item in items) {
      getProtocolTypesAndSupers(item);
    }
    final allEnums = List.of(genEnums);
    final _supers = List.of(genSupers);
    clear();

    final allSupers = _supers.join(',');
    final supersResolve = _supers.map((e) => '${e}Resolve').join(',');
    final impl = allSupers.isNotEmpty ? ',$allSupers' : '';

    final sendPortOwnerName = '${lowIsolateName}SendPortOwner';

    var protocols = '';

    if (allEnums.isNotEmpty) {
      final protocolsBuffer = StringBuffer();
      protocolsBuffer
        ..write('[')
        ..write(allEnums.join(','))
        ..write(']');
      protocols = protocolsBuffer.toString();
    }
    if (isDefault) {
      final doConnectIsolateBuffer = StringBuffer();

      final eachProtocolsBuffer = StringBuffer();
      final createRemoteServer = StringBuffer();
      final yiledAllServer = StringBuffer();

      yiledAllServer.write(
          ''' yield MapEntry('$lowIsolateName',createRemoteServer$upperIsolateName);''');

      /// [Isolate]连接的实现
      for (var item in allConnectToIsolate) {
        final itemLow = lowName(item.isolateName);
        for (var c in item.currentItems) {
          getProtocolTypesAndSupers(c);
        }
        final enums = List.of(genEnums);
        clear();
        createRemoteServer.write(
            'Future<Isolate> createRemoteServer${upperName(item.isolateName)}();');
        doConnectIsolateBuffer.write(
            '''sendPortOwners['$lowIsolateName']!.localSendPort.send(SendPortName(
            '$itemLow', sendPortOwners['$itemLow']!.localSendPort,protocols: allProtocols['$itemLow']));

            ''');

        eachProtocolsBuffer
          ..write("yield const MapEntry('$itemLow',")
          ..write('[')
          ..write(enums.join(','))
          ..write('];');

        yiledAllServer.write('''
         yield MapEntry('$itemLow': createRemoteServer${upperName(item.isolateName)});''');
      }

      var allProcotols =
          '''yield const MapEntry('$lowIsolateName',$protocols);$eachProtocolsBuffer''';

      final setDefaultOwnerGetter = isDefault
          ? 'String get defaultSendPortOwnerName => \'$lowIsolateName\';'
          : '';
      var doConnectIsolate = doConnectIsolateBuffer.isNotEmpty
          ? '''
       void onResumeListen() {
            $doConnectIsolateBuffer
            super.onResumeListen();
          }
      '''
          : '';
      buffer.writeln('''
      
        mixin Multi${upperIsolateName}MessagerMixin on SendEvent,ListenMixin, SendMultiServerMixin /*impl*/ {

          $setDefaultOwnerGetter
          Future<RemoteServer> createRemoteServer$upperIsolateName();
          $createRemoteServer

          Iterable<MapEntry<String,CreateRemoteServer>> createRemoteServerIterable() sync* {
            $yiledAllServer
            yield* super.createRemoteServerIterable();
          }
          Iterable<MapEntry<String, List<Type>>> allProtocolsItreable() sync* {
           $allProcotols
            yield* super.allProtocolsItreable();
          }
         $doConnectIsolate
        }

        ''');
    }

    final creceive =
        genResolveMixinMessager(upperIsolateName, lowIsolateName, group);

    var all = '';
    if (allConnectToIsolate.isNotEmpty) {
      all = 'SendEvent,';
    }
    if (creceive.isNotEmpty) {
      buffer.write('''  abstract class Multi${upperIsolateName}ResolveMain  with
        $all
        ListenMixin,
        Resolve,
        Multi${upperIsolateName}Mixin,
        $supersResolve {}''');
      buffer.write(creceive);
      buffer.write('''
        void onResumeListen() {
          if (remoteSendPort != null)
            remoteSendPort!.send(SendPortName('$lowIsolateName',localSendPort,protocols: $protocols,));
          super.onResumeListen();
        }
      }''');
    } else if (group.connects.isNotEmpty) {
      buffer.write('''

      abstract class Multi${upperIsolateName}ResolveMain  with
        ListenMixin,
        Resolve,
        $supersResolve,
        Multi${upperIsolateName}OnResumeMixin
         {}
      mixin Multi${upperIsolateName}OnResumeMixin on Resolve /*impl*/ {
        void onResumeListen() {
          if (remoteSendPort != null)
            remoteSendPort!.send(SendPortName('$lowIsolateName',localSendPort,protocols: $protocols,));
          super.onResumeListen();
        }
      }''');
    }
    return buffer.toString();
  }

  //// ----------- Resolve mixin Messager -----------------------------------
  String genResolveMixinMessager(
      String upperIsolateName, String lowIsolateName, IsolateGroup group) {
    var connectRecieiveSendPort = '';
    var connectToIsolate = group.connectToGroup.map((e) => e.isolateName);
    if (connectToIsolate.isNotEmpty) {
      final connectTos = connectToIsolate;

      var onReceivedSendPort = '';
      var onClose = '';

      var getSendPortOwnerConnectTos = '';
      final connectToAllCasesBuffer = StringBuffer();
      for (var connectTo in group.connectToGroup) {
        connectToAllCasesBuffer.writeln('''
        case '${connectTo.isolateName}':
        return ${lowName(connectTo.isolateName)}SendPortOwner;''');
      }
      if (connectToAllCasesBuffer.isNotEmpty) {
        getSendPortOwnerConnectTos = '''
      SendPortOwner? getSendPortOwner(isolateName) {
      switch(isolateName) {
        $connectToAllCasesBuffer
        default:
      }
      return super.getSendPortOwner(isolateName);
      }''';
      }

      final cases = connectTos.map((e) => '''
        case '$e':
          ${lowName(e)}SendPortOwner = sendPortOwner;
          break;''').join('\n');
      onReceivedSendPort = '''
              final sendPortOwner = SendPortOwner(
                localSendPort: sendPortName.sendPort,
                remoteSendPort: localSendPort,
              );
              final localProts = sendPortName.protocols;
              if (localProts != null) {
                final prots = getProtocols(sendPortName.name).toList();
                final success = prots.every((e) => localProts.contains(e));
                Log.w(
                    'eventDefault: received \${sendPortName.name}, prots:\${success ? '' : ' not'} matched',
                    onlyDebug: false);
              } else {
                Log.e('\${sendPortName.name} protocols isEmpty', onlyDebug: false);
              }
              switch (sendPortName.name) {
                $cases
                default:
                  super.onListenReceivedSendPort(sendPortName);
                  return;
              }''';
      onClose = connectTos
          .map((e) => '${lowName(e)}SendPortOwner = null;')
          .join('\n');

      final getConnectNames = connectTos
          .map((e) => 'SendPortOwner? ${lowName(e)}SendPortOwner;')
          .join('\n');

      connectRecieiveSendPort = '''
        void onListenReceivedSendPort(SendPortName sendPortName) {
          $onReceivedSendPort
          onResume();
        }

        $getSendPortOwnerConnectTos

        FutureOr<bool> onClose() async {
          $onClose
          return super.onClose();
        }
        ''';

      connectRecieiveSendPort = '''
          $getConnectNames
          $connectRecieiveSendPort
    ''';
    }
    var all = '';
    if (connectRecieiveSendPort.isNotEmpty) {
      all = 'SendEvent,';
    }
    connectRecieiveSendPort = '''
        mixin Multi${upperIsolateName}Mixin on $all Resolve {
          $connectRecieiveSendPort
    ''';
    return connectRecieiveSendPort;
  }

  List<String> getTypes(ClassItem item) {
    final _list = <String>[];
    if (item.methods.isNotEmpty) {
      _list.add(item.className!);
    }
    if (item.separate) {
      _list.addAll(item.supers.expand((e) => getTypes(e)));
    }
    // _list.addAll(item.privateProtocols.expand((e) => getTypes(e)));

    return _list.toSet().toList();
  }

  String writeMessageEnum(ClassItem item, [bool root = false]) {
    final buffer = StringBuffer();

    final _funcs = <String>{};
    _funcs.addAll(item.methods.map((e) => e.name!));
    if (root || item.separate) {
      buffer.writeAll(item.supers.map((e) => writeMessageEnum(e)));
      buffer.writeAll(item.privateProtocols.map((e) => writeMessageEnum(e)));
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
        final privateProtocols = meta
            ?.getField('privateProtocols')
            ?.toListValue()
            ?.map((e) => e.toTypeValue()?.element)
            .whereType<Element>();

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
          if (privateProtocols?.isNotEmpty == true) {
            final privates = <ClassItem>{};
            for (var item in privateProtocols!) {
              if (item is ClassElement) {
                final curent = gen(item, null);
                // final privateinterfaces = item.interfaces
                //     .map((e) => gen(e.element, null))
                //     .whereType<ClassItem>();

                // final privatemixins = item.mixins
                //     .map((e) => gen(e.element, null))
                //     .whereType<ClassItem>();
                if (curent != null) {
                  privates.add(curent);
                }
                // privates
                //   ..addAll(privateinterfaces)
                //   ..addAll(privatemixins);
              }
            }
            _item.privateProtocols = privates.toList();
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
