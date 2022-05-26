bool isSameType<T>(String? name) {
  return getTypeString<T>() == name;
}

String getTypeString<T>() => T.toString();
