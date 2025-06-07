import 'package:analyzer/dart/element/element.dart';
import 'package:nop_annotations/nop_annotations.dart';

bool isSameType<T>(String? name) {
  return getTypeString<T>() == name;
}

String getTypeString<T>() => T.toString();

String? fnName(ExecutableElement? fn, {bool dot = true, String reg = ''}) {
  if (fn != null) {
    if (fn.enclosingElement3 is InterfaceElement) {
      final cls = fn.enclosingElement3 as InterfaceElement;
      var name = cls.name;
      if (reg.isNotEmpty) {
        name = name.replaceAll(RegExp(reg), '');
      }
      if (dot) {
        return '$name.${fn.name}';
      }

      return '${name}_${(fn.name)}';
    }
    if (reg.isNotEmpty) {
      return fn.name.replaceAll(RegExp(reg), '');
    }
    return fn.name;
  }
  return null;
}

ParamNote getParamNote(List<ElementAnnotation> list) {
  for (var item in list) {
    final meta = item.computeConstantValue();
    final metaName = meta?.type?.element?.name;
    if (isSameType<Param>(metaName)) {
      final name = meta!.getField('name')?.toStringValue();
      final isQuery = meta.getField('isQuery')?.toBoolValue();
      final fromJson = meta.getField('fromJson')?.toFunctionValue();
      final toJson = meta.getField('toJson')?.toFunctionValue();
      final toJsonName = meta.getField('toJsonName')?.toStringValue();
      if (name != null && isQuery != null) {
        return ParamNote(name, isQuery, fromJson, toJson, toJsonName);
      }
    }
  }
  return ParamNote('', true, null, null, null);
}

String getMember(ExecutableElement fn, String name) {
  if (fn.enclosingElement is InterfaceElement) {
    final cls = fn.enclosingElement as InterfaceElement;
    final field = cls.getField(name) ?? cls.getGetter(name);
    if (field != null) {
      return '${cls.name}.${field.displayName}';
    }
  }
  return '';
}

class ParamNote {
  ParamNote(
      this.name, this.isQuery, this.fromJson, this.toJson, this.toJsonName);
  final String name;
  final bool isQuery;
  final ExecutableElement? fromJson;
  final ExecutableElement? toJson;
  final String? toJsonName;

  String getName(String baseName) {
    if (name.isEmpty) {
      return baseName;
    }
    return name;
  }
}
