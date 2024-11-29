import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:nop_annotations/nop_annotations.dart';
import 'package:source_gen/source_gen.dart';

import 'type_name.dart';

class ServerGroup {
  ServerGroup(this.serverName);
  final String serverName;
  final connectToOthersGroup = <ServerGroup>{};

  /// 要连接此`serverName`Server
  /// `connects`可能拥有相同的`Server`
  final Set<ClassItem> connects = {};

  /// 当前`serverName`支持的协议
  final Set<ClassItem> currentItems = {};
  void addConnectToGroup(ServerGroup group) {
    connectToOthersGroup.add(group);
  }

  void addConnect(ClassItem item) {
    connects.add(item);
  }

  void addCurerntItem(ClassItem item) {
    currentItems.add(item);
  }

  @override
  String toString() {
    return '$currentItems';
  }
}

class ClassItem {
  String? className;
  ClassItem? parent;

  final supers = <ClassItem>[];
  bool separate = false;
  String messagerType = '';
  final methods = <Methods>[];
  String serverName = '';
  List<String> connectToServer = const [];
  // List<ClassItem> privateProtocols = const [];
  bool isProtocols = false;
  bool isLocal = false;
  @override
  String toString() {
    return '$className';
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
  String replace(String prefex, String source, LibraryReader reader) {
    var name = '';
    source.replaceAllMapped(RegExp('^$prefex<(.*)>\$'), (match) {
      final item = match[1];
      final itemNotNull = '$item'.replaceAll('?', '');
      final currentItem = 'TransferType<$itemNotNull>';
      final itemElement = reader.findType(itemNotNull);

      if (itemElement is ClassElement) {
        useSameReturnType = itemElement.allSupertypes.any((element) => element
            .element.name.contains(currentItem));
      }
      name = useSameReturnType
          ? returnType.toString()
          : '$prefex<TransferType<$item>>';
      return '';
    });
    return name;
  }

  String getReturnNameTransferType(LibraryReader reader) {
    if (_getReturnNameTransferType != null) return _getReturnNameTransferType!;
    var returnTypeName = '';
    final returnName = returnType.toString();

    returnTypeName = replace('FutureOr', returnName, reader);
    if (returnTypeName.isEmpty) {
      returnTypeName = replace('Future', returnName, reader);
    }
    if (returnTypeName.isEmpty) {
      returnTypeName = replace('Stream', returnName, reader);
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

bool useOption(String source, LibraryReader reader) {
  return RegExp('<Option(.*)>\$').hasMatch(source);
}

class ServerEventGeneratorForAnnotation
    extends GeneratorForAnnotation<NopServerEvent> {
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
      final root = gen(element);

      if (root != null) return write(root);
    }

    return '';
  }

  ClassItem? getNonDefaultName(ClassItem item) {
    if (item.serverName.isEmpty) {
      if (item.parent != null) {
        return getNonDefaultName(item.parent!);
      }
      return null;
    }
    return item;
  }

  static String defaultName = 'default';
  String write(ClassItem root) {
    /// root 必须是`default`
    if (root.serverName.isEmpty) {
      root.serverName = '${getDartMemberName(root.className ?? '')}Default';
    }
    defaultName = root.serverName;

    final buffer = StringBuffer();
    buffer.writeln('// ignore_for_file: annotate_overrides\n'
        '// ignore_for_file: curly_braces_in_flow_control_structures');
    buffer.write(writeMessageEnum(root, true));

    final multiItems = <String, ServerGroup>{};

    void add(ClassItem item) {
      final parentItem = getNonDefaultName(item);
      if (parentItem != null && item != parentItem) {
        item.connectToServer = parentItem.connectToServer;
        item.serverName = parentItem.serverName;
      }
      // for (var element in item.privateProtocols) {
      //   element.serverName = item.serverName;
      //   element.connectToServer = item.connectToServer;
      //   element.isProtocols = true;
      // }

      final group = multiItems.putIfAbsent(
          item.serverName, () => ServerGroup(item.serverName));
      if (!group.currentItems.any(
          (e) => e != root && !e.separate && getAllSupers(e).contains(item))) {
        group.addCurerntItem(item);
      }
      // item.privateProtocols.forEach(group.addCurerntItem);
      final connectTo = item.connectToServer;
      for (var connectToServerName in connectTo) {
        if (connectToServerName == item.serverName) continue;
        final other = multiItems.putIfAbsent(
            connectToServerName, () => ServerGroup(connectToServerName));
        other.addConnect(item);
        group.addConnectToGroup(other);
      }

      for (var element in item.supers) {
        add(element);
      }
    }

    add(root);
    final allItems = <ClassItem>[];

    allItems.addAll(root.supers.expand((element) => getTypes(element)));
    if (root.methods.isNotEmpty) {
      allItems.addAll(getTypes(root));
    }
    var hasLocal = false;
    var allItemsMessager = allItems.map((e) {
      hasLocal |= e.isLocal;
      return e.isLocal ? '${e.className}Resolve' : '${e.className}Messager';
    }).join(',');
    allItemsMessager =
        hasLocal ? 'Resolve,$allItemsMessager' : allItemsMessager;
    final rootMessager =
        '${allItemsMessager.isNotEmpty ? ',' : ''} $allItemsMessager';
    buffer
      ..write(genMulitServer(multiItems.values.toList(), rootMessager))
      ..write(writeItems(root, true));

    return buffer.toString();
  }

  List<Methods> getMethods(ClassItem item) {
    final methods = <Methods>[];
    methods.addAll(item.methods);
    if (!item.separate) {
      methods.addAll(item.supers.expand((e) => getMethods(e)));
    }
    return methods;
  }

  List<String?> getSupers(ClassItem item) {
    final supers = <String?>[];
    supers.add(item.className);
    if (!item.separate) {
      supers.addAll(item.supers.expand((e) => getSupers(e)));
    }
    return supers;
  }

  /// 生成`Messager`、`Resolve`
  String writeItems(ClassItem item, [bool root = false]) {
    final buffer = StringBuffer();
    final funcs = <Methods>{};
    final supers = <String>{};

    if (item.separate || root) {
      funcs.addAll(item.methods);
      buffer.writeAll(item.supers.map(writeItems));
    } else {
      funcs.addAll(getMethods(item));
      supers.addAll(getSupers(item).whereType<String>());
    }

    var dynamicFunction = StringBuffer();

    final lowServerName = getDartMemberName(item.serverName);

    if (funcs.isEmpty) return buffer.toString();

    /// ------------ Resolve -------------------------------------

    final list = <String>[];

    final su = supers.isEmpty ? '${item.className}' : supers.join(',');
    var impl = '';
    list.add(su);

    impl = list.join(',');

    final closureBuffer = <String>[];
    for (var f in funcs) {
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
            '$returnName${f.name}(${f.parameters.join(',')}) => throw NopUseDynamicVersionExection("unused function");');
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
            Map<String, List<Type>> getResolveProtocols()  {
              return super.getResolveProtocols()
            ..putIfAbsent('$lowServerName',()=> []).add(${item.messagerType}Message);
            }
            Map<Type,List<Function>> resolveFunctionIterable() {
              return super.resolveFunctionIterable()
              ..[${item.messagerType}Message]= $closureBuffer;
             
            }
        ''');

    buffer.write(dynamicFunction);
    buffer.writeln('\n}\n');

    /// --------------------- Messager -----------------------\
    buffer.write('''
        /// implements [${item.className}]
        mixin ${item.className}Messager on SendEvent,Messager {
          String get $lowServerName => '$lowServerName';
          Map<String,List<Type>> getProtocols() {
            return super.getProtocols()
            ..putIfAbsent($lowServerName,()=> []).add(${item.messagerType}Message);

          }
        ''');
    for (var e in funcs) {
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
        if (useOption(eRetureType.toString(), reader)) {
          buffer.write(
              ' {return sendOption(${item.messagerType}Message.${e.name},$para,serverName:$lowServerName);');
        } else {
          buffer.write(
              ' {return sendMessage(${item.messagerType}Message.${e.name},$para,serverName:$lowServerName);');
        }
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
        list.add('serverName: $lowServerName');
        named = ',${list.join(',')}';
        buffer.write(
            '{return sendMessageStream(${item.messagerType}Message.${e.name},$para$named);');
      } else {
        buffer.write('{');
      }
      buffer.write('}');
    }
    buffer.write('}');

    return buffer.toString();
  }

  /// ------- multi Server generator ----------
  /// 生成多个[Server]mixins
  /// 初始化时检测协议匹配
  /// 子隔离之间通信实现，连接时检测协议
  String genMulitServer(List<ServerGroup> groups, String rootMessager) {
    final buffer = StringBuffer();
    final defaultServer = groups[0];
    final upperServerName = getDartClassName(defaultServer.serverName);
    final create = StringBuffer();
    final connectTo = StringBuffer();
    final prot = StringBuffer();
    final genResolve = StringBuffer();
    final connectToLocal = StringBuffer();

    for (var group in groups) {
      genConnectToServer(group, create, connectTo, connectToLocal, prot,
          (serverName) {
        return groups.firstWhere((element) => element.serverName == serverName);
      });
      genServerResolve(group, genResolve);
    }
    String connectToBuffer = '';
    if (connectTo.isNotEmpty) {
      connectToBuffer = '''
          void onResumeListen() {
            $connectToLocal
            $connectTo
            super.onResumeListen();
          }
          ''';
    }
    final supers = getSuperNames(defaultServer);

    var supersResolve = supers.map((e) => '${e}Resolve').join(',');
    supersResolve = supersResolve.isNotEmpty ? ',$supersResolve' : '';

    var protBuffer = '';
    if (prot.isNotEmpty) {
      protBuffer = '''
          Map<String,RemoteServer> regRemoteServer() {
             return super.regRemoteServer()
            $prot;
          }
        ''';
    }

    buffer.writeln('''
        /// 主入口
        abstract class Multi${upperServerName}MessagerMain with ListenMixin, SendEventMixin, SendMultiServerMixin $rootMessager {
          $create
          $protBuffer
          $connectToBuffer
        }
        ''');

    buffer.write(genResolve);
    return buffer.toString();
  }

  // 生成与其他`serverName`连接的配置
  void genConnectToServer(
      ServerGroup group,
      StringBuffer create,
      StringBuffer connectTo,
      StringBuffer connectToLocal,
      StringBuffer prot,
      ServerGroup Function(String serverName) getGroup) {
    if (group.currentItems.isEmpty) {
      log.warning(
          '\x1B[31merror: 没有找到 ${group.serverName} server, 可能是 connectToServers 拼写错误\x1B[00m');
      return;
    }
    final lowServerName = getDartMemberName(group.serverName);
    final isLocal = group.currentItems.any((element) => element.isLocal);
    if (!isLocal) {
      prot.write('''..['$lowServerName'] = ${lowServerName}RemoteServer''');
      create.write('RemoteServer get ${lowServerName}RemoteServer;');
    }

    var allDone = true;
    for (var item in group.connectToOthersGroup) {
      if (getGroup(item.serverName).currentItems.isEmpty) {
        log.warning('\x1B[31merror: 没有找到 ${item.serverName} 的 server\x1B[00m');
        allDone = false;
        continue;
      }
      final hasLocal = item.currentItems.any((element) => element.isLocal);
      final itemLow = getDartMemberName(item.serverName);
      var localProt = '';
      if (hasLocal) {
        localProt = ''',localProt: localProts['$itemLow']''';
        if (connectToLocal.isEmpty) {
          connectToLocal.write('final localProts = getResolveProtocols();\n');
        }
      }
      connectTo.write('''connect('$lowServerName','$itemLow'$localProt);''');
    }
    if (!allDone) {
      log.warning(
          '\x1B[31merror: 无法完成连接配置, 请检查 [${group.currentItems.join(', ')}] 的 connectToServers\x1B[00m');
    }
  }

  // 获取所有父类的集合
  Set<String> getSuperNames(ServerGroup group) {
    final genSupers = <ClassItem>{};
    bool getSupers(ClassItem innerItem) {
      if (!innerItem.separate) {
        genSupers.add(innerItem);
        return true;
      }

      if (innerItem.methods.isNotEmpty) {
        genSupers.add(innerItem);
        return true;
      }

      for (var element in innerItem.supers) {
        if (element.serverName == group.serverName) {
          if (getSupers(element)) return true;
        }
      }
      return false;
    }

    for (var item in group.currentItems) {
      getSupers(item);
    }

    return genSupers.map((e) => e.className!).toSet();
  }

  void genServerResolve(ServerGroup group, StringBuffer resolveMain) {
    final lowServerName = getDartMemberName(group.serverName);
    final upperServerName = getDartClassName(group.serverName);

    final supers = getSuperNames(group);

    var supersResolve = supers.map((e) => '${e}Resolve').join(',');
    supersResolve = supersResolve.isNotEmpty ? ',$supersResolve' : '';
    var connectToOthers = '';

    if (group.connectToOthersGroup.isNotEmpty) {
      // 要连接其他 `server` 需要 mixin [ResolveMultiRecievedMixin]
      connectToOthers =
          ',SendEventMixin,SendCacheMixin,ResolveMultiRecievedMixin';
      final buffer = StringBuffer();
      final allGroupSupers = <String>{};
      for (var item in group.connectToOthersGroup) {
        final supers = getSuperNames(item);
        allGroupSupers.addAll(supers);
      }
      var supersMessager = allGroupSupers.map((e) => '${e}Messager').join(',');

      buffer.write(supersMessager);
      if (buffer.isNotEmpty) {
        connectToOthers = '$connectToOthers,$buffer';
      }
    }

    resolveMain.write('''
        /// $lowServerName Server
        abstract class Multi${upperServerName}ResolveMain  with
          ListenMixin,
          Resolve
          $connectToOthers
          $supersResolve {
        Multi${upperServerName}ResolveMain({required ServerConfigurations configurations})
          : remoteSendHandle = configurations.sendHandle;
          final SendHandle remoteSendHandle;
          }
        ''');
  }

  List<ClassItem> getAllSupers(ClassItem item) {
    final list = <ClassItem>[];
    if (item.supers.isNotEmpty) {
      list.addAll(item.supers);
      list.addAll(item.supers.expand((element) => getAllSupers(element)));
    }
    return list;
  }

  List<ClassItem> getTypes(ClassItem item) {
    final list = <ClassItem>{};
    if (item.supers.isNotEmpty && item.separate) {
      list.addAll(item.supers.expand((e) => getTypes(e)));
    } else {
      if (item.methods.isNotEmpty || getMethods(item).isNotEmpty) {
        list.add(item);
      }
    }
    // _list.addAll(item.privateProtocols.expand((e) => getTypes(e)));

    return list.toList();
  }

  String writeMessageEnum(ClassItem item, [bool root = false]) {
    final buffer = StringBuffer();

    final funcs = <String>{};
    funcs.addAll(item.methods.map((e) => e.name!));
    // buffer.writeAll(item.privateProtocols.map((e) => writeMessageEnum(e)));
    if (root || item.separate) {
      buffer.writeAll(item.supers.map((e) => writeMessageEnum(e)));
    } else {
      funcs.addAll(item.supers.expand((e) => e.methods.map((e) => e.name!)));
    }
    // _funcs.addAll(item.privateProtocols
    //     .expand((element) => getMethods(element).map((e) => e.name!)));
    if (funcs.isNotEmpty) {
      buffer
        ..write('enum ${item.messagerType}Message {\n')
        ..write(funcs.join(','))
        ..write('\n}\n');
    }
    return buffer.toString();
  }

  ClassItem? genSuperType(InterfaceElement element) {
    if (element.supertype != null &&
        element.supertype!.element.name != 'Object') {
      return gen(element.supertype!.element);
    }
    return null;
  }

  ClassItem? gen(InterfaceElement element, [ClassItem? parent]) {
    final item = ClassItem();
    item.parent = parent;

    bool generate = true;
    element.metadata.any((e) {
      final meta = e.computeConstantValue();
      final type = meta?.type?.element?.name;
      if (isSameType<NopServerEventItem>(type)) {
        final messageName = meta?.getField('messageName')?.toStringValue();
        final separate = meta?.getField('separate')?.toBoolValue();
        generate = meta?.getField('generate')?.toBoolValue() ?? generate;
        final serverName = meta?.getField('serverName')?.toStringValue();
        final connectToServer =
            meta?.getField('connectToServer')?.toListValue();
        // final privateProtocols = meta
        //     ?.getField('privateProtocols')
        //     ?.toListValue()
        //     ?.map((e) => e.toTypeValue()?.element)
        //     .whereType<Element>();
        final isLocal = meta?.getField('isLocal')?.toBoolValue();

        if (messageName != null &&
            separate != null &&
            serverName != null &&
            isLocal != null &&
            connectToServer != null) {
          if (!item.separate) item.separate = separate;
          item.serverName = getDartMemberName(serverName);
          item.isLocal = isLocal;
          if ((parent == null || item.serverName.isNotEmpty) &&
              connectToServer.isNotEmpty) {
            item.connectToServer = connectToServer
                .map((e) => e.toStringValue())
                .whereType<String>()
                .map((e) => getDartMemberName(e))
                .toList();
          }
          // if (privateProtocols?.isNotEmpty == true) {
          // final privates = <ClassItem>{};
          // for (var item in privateProtocols!) {
          //   if (item is ClassElement) {
          //     final curent = gen(item, null);
          // final privateinterfaces = item.interfaces
          //     .map((e) => gen(e.element, null))
          //     .whereType<ClassItem>();

          // final privatemixins = item.mixins
          //     .map((e) => gen(e.element, null))
          //     .whereType<ClassItem>();
          // if (curent != null) {
          // privates.add(curent);
          // }
          // privates
          //   ..addAll(privateinterfaces)
          //   ..addAll(privatemixins);
          //   }
          // }
          // _item.privateProtocols = privates.toList();
          // }

          if (messageName.isNotEmpty) item.messagerType = messageName;
          return true;
        }
      } else if (isSameType<NopServerEvent>(type)) {
        // rootResolveName = meta?.getField('resolveName')?.toStringValue();
        item.separate = true;
      }
      return false;
    });

    if (!generate) return null;

    final ci = genSuperType(element);
    if (ci != null) item.supers.add(ci);

    item.supers.addAll(element.interfaces
        .map((e) => gen(e.element, item))
        .whereType<ClassItem>());

    item.supers.addAll(
        element.mixins.map((e) => gen(e.element, item)).whereType<ClassItem>());

    item.className ??= element.name;
    if (item.messagerType.isEmpty) {
      item.messagerType = element.name;
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
        final type = data?.type?.element?.name;
        if (type == 'NopServerMethod') {
          final isDynamic = data?.getField('isDynamic')?.toBoolValue() ?? false;
          final useTransferType =
              data?.getField('useTransferType')?.toBoolValue() ?? false;
          final unique = data?.getField('unique')?.toBoolValue() ?? false;
          final cached = data?.getField('cached')?.toBoolValue() ?? false;
          method
            ..isDynamic = isDynamic
            ..useTransferType = useTransferType
            ..unique = unique
            ..cached = cached;

          return true;
        }
        return false;
      });
      method.getReturnNameTransferType(reader);

      item.methods.add(method);
    }
    return item;
  }

  // String? rootResolveName;
}

Builder isolateEventBuilder(BuilderOptions options) => SharedPartBuilder(
    [ServerEventGeneratorForAnnotation()], 'nop_isolate_event');

String getToCamel(String name) {
  return name.replaceAllMapped(RegExp('[_-]([A-Za-z]+)'), (match) {
    final data = match[1]!;
    final first = data.substring(0, 1).toUpperCase();
    final second = data.substring(1);
    return '$first$second';
  });
}

String getDartClassName(String name) {
  final camel = getToCamel(name);
  if (camel.length <= 1) return camel.toUpperCase();
  final first = camel.substring(0, 1).toUpperCase();
  final others = camel.substring(1);
  return '$first$others';
}

String getDartMemberName(String name) {
  final camel = getToCamel(name);
  if (camel.length <= 1) return camel.toLowerCase();
  final first = camel.substring(0, 1).toLowerCase();
  final others = camel.substring(1);
  return '$first$others';
}
