import 'dart:convert';
import 'package:crypto/crypto.dart';

class CryptoUtils {
  static String sha256Hash(String input) =>
      sha256.convert(utf8.encode(input)).toString();
}
