import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Fabrica EPUB de mentira para las pruebas.
///
/// Se construyen **en memoria** en lugar de guardar ficheros de ejemplo en el
/// repositorio. Dos razones: no se versiona ni un binario, y —la que de verdad
/// importa— se pueden fabricar a voluntad los EPUB rotos, que son los casos
/// interesantes. Un EPUB sin índice, con el lomo en otro orden o con DRM no se
/// consigue descargando libros; se construye.
Uint8List zipOf(Map<String, Object> entries) {
  final archive = Archive();
  entries.forEach((name, content) {
    archive.add(
      content is String
          ? ArchiveFile.string(name, content)
          : ArchiveFile.bytes(name, content as List<int>),
    );
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// El `META-INF/container.xml` de cualquier EPUB.
String containerFor(String opfPath) =>
    '<?xml version="1.0"?>'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="$opfPath" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>';

/// Un XHTML de capítulo con [body] dentro.
String chapterXhtml(String body, {String title = 'Capítulo'}) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>$title</title>'
    '</head><body>$body</body></html>';

/// Un OPF de EPUB 2, con su NCX.
String opf2({
  String? title = 'El libro',
  String? author = 'Quien sea',
  List<String> spine = const ['c1.xhtml', 'c2.xhtml'],
  String ncxHref = 'toc.ncx',
}) {
  final items = [
    for (var i = 0; i < spine.length; i++)
      '<item id="c$i" href="${spine[i]}" media-type="application/xhtml+xml"/>',
    '<item id="ncx" href="$ncxHref" media-type="application/x-dtbncx+xml"/>',
  ].join();

  final refs = [
    for (var i = 0; i < spine.length; i++) '<itemref idref="c$i"/>',
  ].join();

  return '<?xml version="1.0"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="2.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '${title == null ? '' : '<dc:title>$title</dc:title>'}'
      '${author == null ? '' : '<dc:creator>$author</dc:creator>'}'
      '</metadata>'
      '<manifest>$items</manifest>'
      '<spine toc="ncx">$refs</spine>'
      '</package>';
}

/// Un NCX con un `navPoint` por entrada.
String ncx(Map<String, String> hrefToTitle) {
  final points = [
    for (final entry in hrefToTitle.entries)
      '<navPoint><navLabel><text>${entry.value}</text></navLabel>'
      '<content src="${entry.key}"/></navPoint>',
  ].join();

  return '<?xml version="1.0"?>'
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
      '<navMap>$points</navMap></ncx>';
}

/// Un OPF de EPUB 3, con su documento de navegación.
String opf3({
  String? title = 'El libro',
  List<String> spine = const ['c1.xhtml', 'c2.xhtml'],
  String navHref = 'nav.xhtml',
}) {
  final items = [
    for (var i = 0; i < spine.length; i++)
      '<item id="c$i" href="${spine[i]}" media-type="application/xhtml+xml"/>',
    '<item id="nav" href="$navHref" media-type="application/xhtml+xml" '
        'properties="nav"/>',
  ].join();

  final refs = [
    for (var i = 0; i < spine.length; i++) '<itemref idref="c$i"/>',
  ].join();

  return '<?xml version="1.0"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '${title == null ? '' : '<dc:title>$title</dc:title>'}'
      '</metadata>'
      '<manifest>$items</manifest>'
      '<spine>$refs</spine>'
      '</package>';
}

/// El `nav.xhtml` de EPUB 3.
String navXhtml(Map<String, String> hrefToTitle) {
  final items = [
    for (final entry in hrefToTitle.entries)
      '<li><a href="${entry.key}">${entry.value}</a></li>',
  ].join();

  return '<?xml version="1.0" encoding="utf-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops"><body>'
      '<nav epub:type="toc"><ol>$items</ol></nav></body></html>';
}

/// Un EPUB 2 completo y sano, listo para abrirse.
Map<String, Object> sampleEpub2({String prefix = 'OEBPS/'}) => {
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': containerFor('${prefix}content.opf'),
  '${prefix}content.opf': opf2(),
  '${prefix}toc.ncx': ncx({
    'c1.xhtml': 'El principio',
    'c2.xhtml': 'El final',
  }),
  '${prefix}c1.xhtml': chapterXhtml('<p>Primera página.</p>'),
  '${prefix}c2.xhtml': chapterXhtml('<p>Última página.</p>'),
};
