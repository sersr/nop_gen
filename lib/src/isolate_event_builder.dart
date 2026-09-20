import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:nop/nop.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:source_gen/source_gen.dart';

class ClassItem {
  String? className;
  ClassItem? parent;

  final supers = <ClassItem>[];

  String messagerType = '';
  final methods = <Methods>[];

  bool isProtocols = false;

  List<Methods> getMethods() {
    final methods = <Methods>[];
    methods.addAll(this.methods);

    methods.addAll(supers.expand((e) => e.getMethods()));

    return methods;
  }

  bool canGenerate() {
    return getMethods().isNotEmpty;
  }

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
  bool useTransferType = false;

  FunctionTypedElement? transferType;

  bool get useDynamic => (useTransferType && !useSameReturnType);
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
        useSameReturnType = itemElement.allSupertypes.any(
          (element) => element.element.name!.contains(currentItem),
        );
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

  static final version313 = Version(3, 13, 0);

  bool get support313 {
    return Version.prioritize(langVersion, version313) >= 0;
  }

  Version get langVersion {
    return reader.element.languageVersion.effective;
  }

  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) async {
    reader = library;

    return super.generate(library, buildStep);
  }

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is ClassElement) {
      final root = gen(element);

      if (root != null) return write(root);
    }

    return '';
  }

  String write(ClassItem root) {
    final buffer = StringBuffer();
    buffer.writeln(
      '// ignore_for_file: annotate_overrides\n'
      '// ignore_for_file: curly_braces_in_flow_control_structures',
    );
    buffer.write(writeMessageEnum(root, true));
    buffer.write(writeItems(root, true));
    return buffer.toString();
  }

  List<Methods> getMethods(ClassItem item) {
    return item.getMethods();
  }

  List<String?> getSupers(ClassItem item) {
    final supers = <String?>[];
    supers.add(item.className);

    supers.addAll(item.supers.expand((e) => getSupers(e)));

    return supers;
  }

  /// 生成`Messager`、`Resolve`
  String writeItems(
    ClassItem item, [
    bool root = false,
    bool writeProtocolFns = false,
  ]) {
    final buffer = StringBuffer();
    final funcs = <Methods>{};
    final supers = <String>{};

    if (root) {
      funcs.addAll(item.methods);
      buffer.writeAll(item.supers.map(writeItems));
    } else {
      funcs.addAll(getMethods(item));
      supers.addAll(getSupers(item).whereType<String>());
    }

    final itemName = getDartMemberName(item.className ?? '');

    if (funcs.isEmpty) return buffer.toString();

    /// ------------ Resolve -------------------------------------

    final list = <String>[];

    final su = supers.isEmpty ? '${item.className}' : supers.join(',');

    list.add(su);

    final closureBuffer = <String>[];
    for (var f in funcs) {
      var parasOp = f.parametersNamedUsed.join(',');
      var paras = f.parameters.length == 1 && parasOp.isEmpty
          ? 'args'
          : List.generate(
              f.parameters.length - f.parametersNamedUsed.length,
              (index) => 'args.\$${index + 1}',
            ).join(',');
      if (paras.isNotEmpty && parasOp.isNotEmpty) {
        parasOp = ',$parasOp';
      }
      final tranName = f.name;

      final para = '$paras$parasOp';

      if (f.transferType case var fn?) {
        final prefix = fn.enclosingElement?.displayName.isNotEmpty == true
            ? '${fn.enclosingElement?.displayName}.'
            : '';

        if (fn.formalParameters.isNotEmpty &&
            fn.formalParameters.first.type == f.returnType) {
          closureBuffer.add(
            '(args) => $itemName.$tranName($para).then($prefix${fn.name})',
          );
          continue;
        } else {
          print('error: $prefix${fn.name} ignore.');
        }
      }
      if (para == 'args') {
        closureBuffer.add('$itemName.$tranName');
      } else {
        closureBuffer.add('(args) => $itemName.$tranName($para)');
      }
    }

    if (writeProtocolFns) {
      return closureBuffer.toString();
    }

    final messager = 'messager';
    final protocol = '${item.messagerType}Message';

    /// --------------------- Messager -----------------------\
    buffer.write('''
        final class ${item.className}Messager extends MessageItem with  ${item.className}MessagerMixin implements ${item.className} {
          ${item.className}Messager();
        }
        ''');
    buffer.write('''
        mixin ${item.className}MessagerMixin implements ${item.className} {
          final Type protocol = ${item.messagerType}Message;
          Messager get messager;
        ''');

    for (var e in funcs) {
      final returnType = e.returnType;
      final tranName = e.name;

      buffer.write('$returnType $tranName(${e.parameters.join(',')})');
      final para = e.parametersMessageList.isEmpty
          ? 'null'
          : e.parametersMessageList.length == 1 && !e.hasNamed
          ? e.parametersMessageList.first
          : '(${e.parametersMessageList.join(',')})';
      final eRetureType = e.returnType!;
      if (eRetureType.isDartAsyncFuture || eRetureType.isDartAsyncFutureOr) {
        if (useOption(eRetureType.toString(), reader)) {
          buffer.write(
            ' {return $messager.sendOption(${item.messagerType}Message.${e.name},$para,protocol:$protocol);',
          );
        } else {
          buffer.write(
            ' {return $messager.sendMessage(${item.messagerType}Message.${e.name},$para,protocol:$protocol);',
          );
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
        list.add('protocol: $protocol');
        named = ',${list.join(',')}';
        buffer.write(
          '{return $messager.sendMessageStream(${item.messagerType}Message.${e.name},$para$named);',
        );
      } else {
        buffer.write('{');
      }
      buffer.write('}');
    }
    buffer.write('}');

    return buffer.toString();
  }

  String writeMessageEnum(ClassItem item, [bool root = false]) {
    final buffer = StringBuffer();

    final funcs = <String>{};
    funcs.addAll(item.methods.map((e) => e.name!));

    if (root) {
      buffer.writeAll(item.supers.map((e) => writeMessageEnum(e)));
    } else {
      funcs.addAll(item.supers.expand((e) => e.methods.map((e) => e.name!)));
    }

    if (funcs.isNotEmpty) {
      final lowName = getDartMemberName(item.className ?? '');
      buffer
        ..write('enum ${item.messagerType}Message {\n')
        ..write(funcs.join(','));
      buffer.write(';');

      buffer.write(
        "static ResolveItem getResolve({required ${item.messagerType} $lowName}) {"
        "return ResolveItem(protocol: ${item.messagerType}Message, protocolFns: ${writeItems(item, false, true)});"
        "}",
      );

      buffer.write('''

static IsolateRunner<${item.messagerType}Messager> getMessage<T>(
  RemoteServer<T> remoteServer,
  ) {
    return IsolateRunner(
      remoteServer: remoteServer,
      messageItem: ${item.messagerType}Messager()
      );
    }
''');
      buffer.write('''
static ${item.messagerType}Messager getResolveMessage() => ${item.messagerType}Messager();
''');

      buffer.write('\n}\n');
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

    final ci = genSuperType(element);
    if (ci != null) item.supers.add(ci);

    item.supers.addAll(
      element.interfaces
          .map((e) => gen(e.element, item))
          .whereType<ClassItem>(),
    );

    item.supers.addAll(
      element.mixins.map((e) => gen(e.element, item)).whereType<ClassItem>(),
    );

    item.className ??= element.name;
    if (item.messagerType.isEmpty) {
      item.messagerType = element.name!;

      element.fields;
    }

    for (var methodElement in element.methods) {
      if (methodElement.isStatic) continue;

      final method = Methods();

      method.name = methodElement.name;
      if (methodElement.name!.startsWith('_')) {
        continue;
      }
      method.returnType = methodElement.returnType;

      final parameters = <String>[];
      final parametersMessage = <String>[];
      final parametersPosOrNamed = <String>[];
      final parametersNamedUsed = <String>[];
      var count = -1;
      for (var item in methodElement.formalParameters) {
        count++;
        parametersMessage.add(item.name ?? '');
        final requiredValue = item.isRequiredNamed ? 'required ' : '';
        final defaultValue = item.hasDefaultValue
            ? ' = ${item.defaultValueCode}'
            : '';
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

      methodElement.metadata.annotations.any((element) {
        final data = element.computeConstantValue();
        final type = data?.type?.element?.name;
        if (type == 'NopServerMethod') {
          // final isDynamic = data?.getField('isDynamic')?.toBoolValue() ?? false;
          // final useTransferType =
          //     data?.getField('useTransferType')?.toBoolValue() ?? false;
          final transferType = data
              ?.getField('transferType')
              ?.toFunctionValue();
          final unique = data?.getField('unique')?.toBoolValue() ?? false;
          final cached = data?.getField('cached')?.toBoolValue() ?? false;
          method
            ..useTransferType = transferType != null
            ..transferType = transferType
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
}

Builder isolateEventBuilder(BuilderOptions options) => SharedPartBuilder([
  ServerEventGeneratorForAnnotation(),
], 'nop_isolate_event');

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
