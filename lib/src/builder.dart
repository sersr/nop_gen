// ignore_for_file: library_private_types_in_public_api

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:nop_annotations/nop_annotations.dart';
import 'package:nop_gen/src/type_name.dart';
import 'package:source_gen/source_gen.dart';

class _ColumnInfo {
  _ColumnInfo();
  String? name;
  String? nameDb;
  String? type;
  String? typeJson;

  bool? _isPrimaryKey;
  static const _map = {
    'String': 'TEXT',
    'int': 'INTEGER',
    'double': 'DOUBLE',
    'List<int>': 'BLOB',
    'bool': 'INTEGER',
    'DateTime': 'TEXT'
  };
  bool get isPrimaryKey => _isPrimaryKey ?? false;
  bool get isBool => type == 'bool';
  bool get isJson => typeJson != null;
  String? get typeDb => _map[type];
}

String firstToLower(String s) {
  return s.substring(0, 1).toLowerCase() + s.substring(1);
}

class GenNopGeneratorForAnnotation extends GeneratorForAnnotation<NopDb> {
  @override
  String generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    final buffer = StringBuffer();
    buffer
      ..writeln('// ignore_for_file: curly_braces_in_flow_control_structures')
      ..writeln('// ignore_for_file: non_constant_identifier_names\n\n');

    final tables = <DartType?>[];

    if (element is ClassElement) {
      final dbName = element.name;
      buffer.write('abstract class _Gen$dbName extends \$Database {\n');

      for (final i in element.metadata) {
        final nopDbItem = i.computeConstantValue();
        if (nopDbItem != null) {
          final nop = nopDbItem.type?.getDisplayString(withNullability: false);

          if (isSameType<NopDb>(nop)) {
            final typetables = nopDbItem.getField('tables')?.toListValue();

            if (typetables != null && typetables.isNotEmpty) {
              tables.addAll(typetables.map((e) => e.toTypeValue()));
            }
          }
        }
      }

      final realDbTables = <String>[];
      final realDbTablesName = <String>[];
      final tablesList = <String>[];

      for (var element in tables) {
        final e = element?.element;

        if (e is ClassElement) {
          var userTable = e.name;
          // auto gen
          var genDbName = userTable;
          var databaseTable = 'Gen$genDbName';
          for (final medata in e.metadata) {
            final cs = medata.computeConstantValue();
            final tbName = cs?.getField('tableName')?.toStringValue();
            final table = cs?.getField('name')?.toStringValue();
            if (table != null && table.isNotEmpty) {
              userTable = table;
              genDbName = userTable;
              databaseTable = 'Gen$genDbName';
            }
            if (tbName != null && tbName.isNotEmpty) {
              // use config
              databaseTable = tbName;
              genDbName = databaseTable;
            }
          }
          realDbTables.add(databaseTable);
          realDbTablesName.add(genDbName);
          final columnInfos = getCols(e.fields);

          tablesList.add(createTable(userTable, databaseTable, columnInfos));
        }
      }

      final lrealTables = realDbTablesName.map((e) => firstToLower(e));
      // member: _tables
      buffer
        ..write('late final _tables = <DatabaseTable>[${lrealTables.join(',')}];\n')
        ..write(writeOver)
        ..write('List<DatabaseTable> get tables => _tables;\n\n');

      var count = 0;
      final userToDb = lrealTables.map((e) {
        count++;
        return 'late final $e = ${realDbTables[count - 1]}(this);\n';
      });

      buffer
        ..write(userToDb.join())
        ..write('\n\n}\n')
        ..writeAll(tablesList);
    }
    return buffer.toString();
  }

  String genDatabase() {
    final buffer = StringBuffer();

    return buffer.toString();
  }

  String createTable(
      String userTableName, String databaseTableName, List<_ColumnInfo> columnInfos) {
    final buffer = StringBuffer();

    buffer.write(genTable(columnInfos, userTableName));
    buffer.write(genTableDb(columnInfos, userTableName, databaseTableName));
    buffer.write(genStatement(columnInfos, userTableName, databaseTableName));
    return buffer.toString();
  }
}

const writeOver = '\n@override\n';

String genTable(List<_ColumnInfo> columnInfos, String className) {
  final buffer = StringBuffer();
  // final _col = columnInfos.map((e) => 'this.${e.name}');

  // final _parItem = columnInfos
  //     .map((e) => '$writeOver' 'final ${e.type} ${e.name};\n')
  //     .toList()
  //     .join('\n');

  final toMap = columnInfos.map((e) {
    if (e.isJson) {
      return '\'${e.nameDb}\': _${e.typeJson}ToMap(table.${e.name})';
    }
    return '\'${e.nameDb}\': table.${e.name}';
  }).join(',');
  // buffer
  //   ..write('class _$className extends $className {\n')
  //   ..write('_$className({\n')
  //   ..write('${_col.join(',')}')
  //   ..write('}):super._();\n\n')
  //   ..write(writeOver)
  //   ..write('Map<String,dynamic> toJson(){\n')
  //   ..write('return {$_toMap};\n}\n')
  //   ..write(_parItem)
  //   ..write('}\n');
  buffer
    ..write('Map<String,dynamic> _${className}_toJson($className table){\n')
    ..write('return {$toMap};\n}\n');
  // ..write('}\n\n');

  return buffer.toString();
}

String genTableDb(List<_ColumnInfo> columnInfos, String userTableName, String databaseTableName) {
  ///----------- DatabaseTable
  final buffer = StringBuffer();

  buffer
    ..write(
        'class $databaseTableName extends DatabaseTable<$userTableName, $databaseTableName> {\n')
    ..write('$databaseTableName(\$Database db) : super(db);\n')
    // getter: table
    ..write(writeOver)
    ..write('final table = \'$userTableName\';\n');

  final c = columnInfos.map((e) => 'final ${e.name} = \'${e.nameDb}\';\n').join();
  // members
  buffer.write(c);
  // function: createTable
  buffer.write('\n');
  final tableName = firstToLower(userTableName);
  final u = columnInfos
      .map((e) => 'if($tableName.${e.name} != null) update.${e.name}.set($tableName.${e.name});\n');
  // update
  buffer
    ..write('void update$userTableName(UpdateStatement<$userTableName,')
    ..write('$databaseTableName> update,$userTableName $tableName){')
    ..write(u.join('\n'))
    ..write('}\n\n');

  // createTable
  buffer
    ..write(writeOver)
    ..write('String createTable() {\n');
  final members = columnInfos.map((e) {
    final primaryKey = e.isPrimaryKey ? ' PRIMARY KEY' : '';
    return '\$${e.name} ${e.typeDb}$primaryKey';
  });

  const s = 'return \'CREATE TABLE IF NOT EXISTS \$table (';
  const length = 4 + s.length;
  final m = members.join(', ').split(' ');

  buffer
    ..write(s)
    ..write(breakLines(m, length, 8))
    ..write(')\';\n}\n');

  // function: toTable
  final parMap = columnInfos.map((e) {
    if (e.isBool) {
      return '${e.name}: Table.intToBool(map[\'${e.nameDb}\'] as int?)';
    } else if (e.type == 'DateTime') {
      return '${e.name}: DateTime.tryParse(map[\'${e.nameDb}\'] as String? ??\'\')';
    } else if (e.isJson) {
      return '${e.name}: _${e.typeJson}ToTable(map[\'${e.nameDb}\'])';
    }
    return '${e.name}: map[\'${e.nameDb}\'] as ${e.type}?';
  }).join(',');

  buffer
    ..write('static $userTableName mapToTable(Map<String,dynamic> map) =>\n')
    ..write(' $userTableName($parMap);\n')
    ..write(writeOver)
    ..write('List<$userTableName> toTable(Iterable<Map<String,Object?>> query) => ')
    ..write('query.map((e)=> mapToTable(e)).toList();')
    // ..write(writeOver)
    // ..write('Map<String,dynamic> toJson($userTableName table) => ')
    // ..write('table.toJson();')
    ..write('\n}\n\n');
  return buffer.toString();
}

final statements = ['QueryStatement', 'UpdateStatement', 'InsertStatement'];
String genStatement(List<_ColumnInfo> columnInfos, String userTableName, String databaseTableName) {
  final buffer = StringBuffer();
  String lowTableName;
  if (databaseTableName.contains('Gen')) {
    lowTableName = '${userTableName[0].toLowerCase()}${userTableName.substring(1)}';
  } else {
    lowTableName = '${databaseTableName[0].toLowerCase()}${databaseTableName.substring(1)}';
  }
  buffer.write(
      'extension ItemExtension$userTableName<T extends ItemExtension<$databaseTableName>> on T {\n');

  final items = columnInfos.map((e) => 'T get ${e.name} => item(table.${e.name}) as T; \n');
  final tableItems = columnInfos.map((e) => 'T get ${lowTableName}_${e.name} => ${e.name}; \n');
  buffer
    ..writeAll(items, '\n')
    ..write('\n\n')
    ..writeAll(tableItems, '\n')
    ..write('}\n\n');

  final joinTableItems = columnInfos
      .map((e) => 'J get ${lowTableName}_${e.name} => joinItem(joinTable.${e.name}) as J; \n');
  buffer
    ..write('extension JoinItem$userTableName<J extends JoinItem<$databaseTableName>> on J{\n')
    ..writeAll(joinTableItems, '\n')
    ..write('}\n\n');

  return buffer.toString();
}

List<_ColumnInfo> getCols(List<FieldElement> map) {
  return map.where((element) => element.name != 'allItems').map((e) {
    final info = _ColumnInfo();
    info.name = e.name;

    for (var i in e.metadata) {
      final nopDbItemMeta = i.computeConstantValue();

      if (nopDbItemMeta != null) {
        final typeName = nopDbItemMeta.type?.getDisplayString(withNullability: false);
        if (isSameType<NopDbItem>(typeName)) {
          final name = nopDbItemMeta.getField('name')?.toStringValue();

          final addPrimaryKey = nopDbItemMeta.getField('primaryKey')?.toBoolValue();
          final type = nopDbItemMeta.getField('type')?.toTypeValue();
          if (addPrimaryKey != null && name != null) {
            info._isPrimaryKey = addPrimaryKey;
            info.nameDb = name.isEmpty ? e.name : name;
            info.type = type?.getDisplayString(withNullability: false);
            break;
          }
        }
      }
    }
    info.nameDb ??= e.name;
    final type = e.type.getDisplayString(withNullability: false);
    if (info.type != null) {
      info.typeJson = type;
    }
    info.type ??= type;
    if (info.typeDb == null && !info.isJson) {
      // ignore: avoid_print
      print('不支持的类型没有提供具体类型 如：`@NopDbItem(type: String)`');
    }
    return info;
  }).toList();
}

String breakLines(Iterable i, [int start = 0, int leftBound = 0]) {
  final mi = i.iterator;
  final buffer = StringBuffer();
  var length = start;

  mi.moveNext();
  buffer.write(mi.current);

  length += mi.current.toString().length;

  while (mi.moveNext()) {
    if (length + mi.current.length > 78) {
      buffer.write(' \'\n\'');
      length = leftBound;
    }
    if (length != leftBound) {
      buffer.write(' ');
      length += 1;
    }

    length += mi.current.toString().length;
    buffer.write(mi.current);
  }

  return buffer.toString();
}

Builder nopBuilder(BuilderOptions options) =>
    SharedPartBuilder([GenNopGeneratorForAnnotation()], 'nop_db');
