import 'dart:typed_data';

/// DEX 文件解析结果
class DexInfo {
  final bool valid;
  final String? error;
  final int fileSize;
  final int headerSize;
  final String? version;
  final List<DexClass> classes;
  final int stringCount;
  final int typeCount;
  final int protoCount;
  final int fieldCount;
  final int methodCount;

  const DexInfo({
    this.valid = false,
    this.error,
    this.fileSize = 0,
    this.headerSize = 0,
    this.version,
    this.classes = const [],
    this.stringCount = 0,
    this.typeCount = 0,
    this.protoCount = 0,
    this.fieldCount = 0,
    this.methodCount = 0,
  });
}

class DexClass {
  final String name;
  final int accessFlags;
  final String? superClass;
  final int methodCount;
  final int fieldCount;
  final List<DexMethod> methods;

  const DexClass({
    required this.name,
    this.accessFlags = 0,
    this.superClass,
    this.methodCount = 0,
    this.fieldCount = 0,
    this.methods = const [],
  });
}

class DexMethod {
  final String name;
  final String returnType;
  final List<String> parameters;

  const DexMethod({
    required this.name,
    this.returnType = 'void',
    this.parameters = const [],
  });

  String get signature => '$returnType $name(${parameters.join(', ')})';
}

/// 简易 DEX 文件解析器
class DexParser {
  static bool isDex(Uint8List data) {
    if (data.length < 8) return false;
    return data[0] == 0x64 && // 'd'
        data[1] == 0x65 && // 'e'
        data[2] == 0x78 && // 'x'
        data[3] == 0x0A;   // '\n'
  }

  static DexInfo parse(Uint8List data) {
    if (!isDex(data)) {
      return const DexInfo(valid: false, error: 'Not a DEX file');
    }

    try {
      final reader = _ByteReader(data);
      reader.offset = 0;

      // Magic + version (8 bytes)
      final magic = String.fromCharCodes(data.sublist(0, 4));
      final ver = String.fromCharCodes(data.sublist(4, 7));
      final version = '$magic $ver';
      reader.skip(8);

      // Checksum (skip for now)
      reader.readU32();

      // Signature (20 bytes SHA1)
      final signature = data.sublist(reader.offset, reader.offset + 20);
      reader.skip(20);

      final fileSize = reader.readU32();
      final headerSize = reader.readU32();
      reader.readU32(); // endian_tag

      // Skip link section
      reader.readU32(); // link_size
      reader.readU32(); // link_off

      reader.readU32(); // map_off

      final stringIdsSize = reader.readU32();
      final stringIdsOff = reader.readU32();
      final typeIdsSize = reader.readU32();
      final typeIdsOff = reader.readU32();
      final protoIdsSize = reader.readU32();
      final protoIdsOff = reader.readU32();
      final fieldIdsSize = reader.readU32();
      final fieldIdsOff = reader.readU32();
      final methodIdsSize = reader.readU32();
      final methodIdsOff = reader.readU32();
      final classDefsSize = reader.readU32();
      final classDefsOff = reader.readU32();
      // dataSize, dataOff
      reader.readU32();
      reader.readU32();

      // Read strings
      final strings = <int, String>{};
      for (var i = 0; i < stringIdsSize && i < 10000; i++) {
        reader.offset = stringIdsOff + i * 4;
        final strOff = reader.readU32();
        reader.offset = strOff;
        final str = reader.readMutf8();
        strings[i] = str;
      }

      // Read types
      final types = <int, String>{};
      for (var i = 0; i < typeIdsSize && i < 10000; i++) {
        reader.offset = typeIdsOff + i * 4;
        final strIdx = reader.readU32();
        types[i] = strings[strIdx] ?? '?';
      }

      // Read protos
      final protos = <int, _ProtoInfo>{};
      for (var i = 0; i < protoIdsSize && i < 10000; i++) {
        reader.offset = protoIdsOff + i * 12;
        final shortyIdx = reader.readU32();
        final returnTypeIdx = reader.readU32();
        final paramsOff = reader.readU32();
        final returnType = types[returnTypeIdx] ?? 'void';
        final params = <String>[];
        if (paramsOff != 0) {
          reader.offset = paramsOff;
          final paramCount = reader.readU32();
          for (var j = 0; j < paramCount && j < 100; j++) {
            final typeIdx = reader.readU16();
            params.add(types[typeIdx] ?? '?');
          }
        }
        protos[i] = _ProtoInfo(
          shorty: strings[shortyIdx] ?? '?',
          returnType: returnType,
          params: params,
        );
      }

      // Read methods
      final methods = <int, DexMethod>{};
      for (var i = 0; i < methodIdsSize && i < 50000; i++) {
        reader.offset = methodIdsOff + i * 8;
        final classIdx = reader.readU16();
        final protoIdx = reader.readU16();
        final nameIdx = reader.readU32();
        final name = strings[nameIdx] ?? '?';
        final proto = protos[protoIdx] ?? _ProtoInfo();
        methods[i] = DexMethod(
          name: name,
          returnType: proto.returnType,
          parameters: proto.params,
        );
      }

      // Read classes
      final classes = <DexClass>[];
      for (var i = 0; i < classDefsSize && i < 10000; i++) {
        reader.offset = classDefsOff + i * 32;
        final classIdx = reader.readU32();
        final accessFlags = reader.readU32();
        final superclassIdx = reader.readU32();
        reader.readU32(); // interfaces_off
        reader.readU32(); // source_file_idx
        reader.readU32(); // annotations_off
        final classDataOff = reader.readU32();
        reader.readU32(); // static_values_off

        final className = types[classIdx] ?? '?';
        final superName = superclassIdx != 0xFFFFFFFF ? types[superclassIdx] : null;

        var methodCount = 0;
        var fieldCount = 0;
        final classMethods = <DexMethod>[];

        if (classDataOff != 0) {
          reader.offset = classDataOff;
          final staticFieldsSize = reader.readUleb128();
          final instanceFieldsSize = reader.readUleb128();
          final directMethodsSize = reader.readUleb128();
          final virtualMethodsSize = reader.readUleb128();

          fieldCount = staticFieldsSize + instanceFieldsSize;

          // Skip fields
          for (var j = 0; j < staticFieldsSize + instanceFieldsSize; j++) {
            reader.readUleb128(); // field_idx_diff
            reader.readUleb128(); // access_flags
          }

          // Direct methods
          var lastMethodIdx = 0;
          for (var j = 0; j < directMethodsSize; j++) {
            final diff = reader.readUleb128();
            lastMethodIdx += diff;
            reader.readUleb128(); // access_flags
            reader.readUleb128(); // code_off
            final m = methods[lastMethodIdx];
            if (m != null) classMethods.add(m);
          }

          // Virtual methods
          for (var j = 0; j < virtualMethodsSize; j++) {
            final diff = reader.readUleb128();
            lastMethodIdx += diff;
            reader.readUleb128(); // access_flags
            reader.readUleb128(); // code_off
            final m = methods[lastMethodIdx];
            if (m != null) classMethods.add(m);
          }

          methodCount = directMethodsSize + virtualMethodsSize;
        }

        classes.add(DexClass(
          name: className,
          accessFlags: accessFlags,
          superClass: superName,
          methodCount: methodCount,
          fieldCount: fieldCount,
          methods: classMethods,
        ));
      }

      return DexInfo(
        valid: true,
        version: version,
        fileSize: fileSize,
        headerSize: headerSize,
        stringCount: stringIdsSize,
        typeCount: typeIdsSize,
        protoCount: protoIdsSize,
        fieldCount: fieldIdsSize,
        methodCount: methodIdsSize,
        classes: classes,
      );
    } catch (e) {
      return DexInfo(valid: false, error: 'Parse error: $e');
    }
  }
}

/// Little-endian byte reader
class _ByteReader {
  final Uint8List data;
  int offset = 0;

  _ByteReader(this.data);

  void skip(int n) => offset += n;

  int readU8() => data[offset++];

  int readU16() {
    final v = data[offset] | (data[offset + 1] << 8);
    offset += 2;
    return v;
  }

  int readU32() {
    final v = data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
    offset += 4;
    return v;
  }

  int readUleb128() {
    var result = 0;
    var shift = 0;
    while (true) {
      final b = data[offset++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }

  /// Read MUTF-8 encoded string at current offset
  String readMutf8() {
    // Read uleb128 length
    final utf16Len = readUleb128();
    if (utf16Len == 0) return '';

    final bytes = <int>[];
    while (true) {
      final b = data[offset++];
      if (b == 0) break;
      bytes.add(b);
    }

    // Decode modified UTF-8
    final chars = <int>[];
    var i = 0;
    while (i < bytes.length) {
      final b = bytes[i++];
      if ((b & 0x80) == 0) {
        // 1-byte: 0xxxxxxx
        chars.add(b);
      } else if ((b & 0xE0) == 0xC0) {
        // 2-byte: 110xxxxx 10xxxxxx
        final b2 = bytes[i++];
        chars.add(((b & 0x1F) << 6) | (b2 & 0x3F));
      } else if ((b & 0xF0) == 0xE0) {
        // 3-byte: 1110xxxx 10xxxxxx 10xxxxxx
        final b2 = bytes[i++];
        final b3 = bytes[i++];
        chars.add(((b & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F));
      } else {
        // 4-byte or error, skip
        if (i < bytes.length) i++;
        if (i < bytes.length) i++;
        chars.add(0xFFFD);
      }
    }

    return String.fromCharCodes(chars);
  }
}

class _ProtoInfo {
  final String shorty;
  final String returnType;
  final List<String> params;

  const _ProtoInfo({
    this.shorty = '?',
    this.returnType = 'void',
    this.params = const [],
  });
}
