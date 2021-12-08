import 'dart:async';

import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:nop_annotations/nop_annotations.dart';

import 'package:source_gen/source_gen.dart';
import 'package:analyzer/dart/element/element.dart';

class IsolateGroup {
  IsolateGroup(this.isolateName);
  final String isolateName;
  final connectToOthersGroup = <IsolateGroup>{};

  /// 要连接此`isolateName`Isolate
  /// `connects`可能拥有相同的`isolate`
  final Set<ClassItem> connects = {};

  /// 当前`isolateName`支持的协议
  final Set<ClassItem> currentItems = {};
  void addConnectToGroup(IsolateGroup group) {
    connectToOthersGroup.add(group);
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
  bool isProtocols = false;
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
        element.isProtocols = true;
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

    if (item.separate || root) {
      buffer.writeAll(item.supers.map((e) => writeItems(e)));
    } else {
      _funcs.addAll(item.supers.expand((e) {
        return getMethods(e);
      }));
      _supers.addAll(getSupers(item).whereType<String>());
    }
    if (item.privateProtocols.isNotEmpty) {
      buffer.writeAll(item.privateProtocols.map((e) => writeItems(e)));
    }

    final _implements = <String>[];
    var dynamicFunction = StringBuffer();

    final lowIsolateName = lowName(item.isolateName);

    /// ------------ Resolve -------------------------------------
    if (_funcs.isNotEmpty) {
      final _list = <String>[];

      final su = _supers.isEmpty ? '${item.className}' : _supers.join(',');
      var impl = '';
      _list.add(su);
      if (_implements.isNotEmpty) {
        _list.add(_implements.join(','));
      }
      impl = _list.join(',');

      final closureBuffer = <String>[];
      for (var f in _funcs) {
        var parasOp = f.parametersNamedUsed.join(',');
        var paras = f.parameters.length == 1 && parasOp.isEmpty
            ? 'args'
            : List.generate(f.parameters.length - f.parametersNamedUsed.length,
                (index) => 'args[$index]').join(',');
        if (paras.isNotEmpty && parasOp.isNotEmpty) {
          parasOp = ',$parasOp';
        }
        final tranName = f.useDynamic ? '${f.name}Dynamic' : f.name;
        if (f.useTransferType) {
          const returnName = '';
          dynamicFunction.write(
              '$returnName${f.name}(${f.parameters.join(',')}) => throw NopUseDynamicVersionExection("不要手动调用");');
        }
        if (f.useDynamic) {
          final name = f.getReturnNameTransferType(reader);
          dynamicFunction
              .write('$name ${f.name}Dynamic(${f.parameters.join(',')});');
        }
        final para = '$paras$parasOp';
        if (para == 'args') {
          closureBuffer.add('$tranName');
        } else {
          closureBuffer.add('(args) => $tranName($para)');
        }
      }
      buffer.write(
          'mixin ${item.className}Resolve on Resolve implements $impl {\n');
      buffer.writeln('''
            Iterable<MapEntry<String, Type>> getResolveProtocols() sync* {
              yield const MapEntry('$lowIsolateName',${item.messagerType}Message);
              yield* super.getResolveProtocols();
            }
            Iterable<MapEntry<Type,List<Function>>> resolveFunctionIterable()sync* {
              yield MapEntry(${item.messagerType}Message, $closureBuffer);
              yield* super.resolveFunctionIterable();
            }
        ''');

      buffer.write(dynamicFunction);
      buffer.writeln('\n}\n');
      var sendEvent = 'sendEvent';

      /// --------------------- Messager -----------------------\
      buffer.write('''
        /// implements [${item.className}]
        mixin ${item.className}Messager on SendEvent {
          SendEvent get sendEvent;
          String get $lowIsolateName => '$lowIsolateName';
          Iterable<MapEntry<String,Type>> getProtocols() sync*{
            yield MapEntry($lowIsolateName,${item.messagerType}Message);
            yield* super.getProtocols();
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
    final connectToOtherIsolates = group.connectToOthersGroup;

    final buffer = StringBuffer();

    var isDefault = group.isolateName.toLowerCase().contains('default');

    final genSupers = <String>{};
    void clear() {
      genSupers.clear();
    }

    void getSupers(ClassItem innerItem) {
      if (innerItem.methods.isNotEmpty) {
        if (innerItem.parent?.separate == true) {
          genSupers.add(innerItem.className!);
        }
      }
      if (innerItem.isProtocols) {
        genSupers.add(innerItem.className!);
        return;
      }
      for (var element in innerItem.supers) {
        if (element.isolateName == isolateName) {
          getSupers(element);
        }
      }
    }

    // 获取[method]非空的所有协议[enum],
    for (var item in items) {
      getSupers(item);
    }
    final _supers = List.of(genSupers);
    clear();

    final allSupers = _supers.join(',');
    var supersResolve = _supers.map((e) => '${e}Resolve').join(',');
    supersResolve = supersResolve.isNotEmpty ? ',$supersResolve' : '';
    // ignore: unused_local_variable
    final impl = allSupers.isNotEmpty ? ',$allSupers' : '';

    if (isDefault) {
      final doConnectIsolateBuffer = StringBuffer();

      final createRemoteServer = StringBuffer();
      final yiledAllServer = StringBuffer();

      yiledAllServer.write(
          ''' yield MapEntry('$lowIsolateName',createRemoteServer$upperIsolateName);''');

      /// [Isolate]连接的实现
      for (var item in connectToOtherIsolates) {
        final itemLow = lowName(item.isolateName);
        for (var c in item.currentItems) {
          getSupers(c);
        }
        clear();
        createRemoteServer.write(
            'Future<RemoteServer> createRemoteServer${upperName(item.isolateName)}();');
        doConnectIsolateBuffer.write(
            '''sendPortOwners['$lowIsolateName']!.localSendPort.send(SendPortName(
            '$itemLow', sendPortOwners['$itemLow']!.localSendPort,protocols: getServerProtocols('$itemLow')));
            ''');

        yiledAllServer.write('''
         yield MapEntry('$itemLow', createRemoteServer${upperName(item.isolateName)});''');
      }

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
          $doConnectIsolate
        }
        abstract class Multi${upperIsolateName}ResolveMain  with
        SendEvent,
        ListenMixin,
        Resolve,
        ResolveMultiRecievedMixin 
        $supersResolve {}
        ''');
    } else if (group.connects.isNotEmpty) {
      buffer.write('''
      abstract class Multi${upperIsolateName}ResolveMain  with
        ListenMixin,
        Resolve 
        $supersResolve
         {}''');
    }
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
          if (!_item.separate) _item.separate = separate;
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
        _item.separate = true;
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
