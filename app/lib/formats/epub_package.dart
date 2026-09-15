import 'package:xml/xml.dart';

import '../domain/book_source.dart';
import 'epub_archive.dart';

/// Un documento del lomo: un fichero XHTML que el lector enseña como capítulo.
class SpineDocument {
  const SpineDocument({
    required this.href,
    required this.title,
    required this.mediaType,
  });

  /// Ruta relativa a la carpeta del OPF.
  final String href;

  final String title;
  final String mediaType;
}

/// El fichero de paquete de un EPUB, ya interpretado.
///
/// Un EPUB real viene mal formado con muchísima frecuencia: sin título, con el
/// índice roto, con el lomo en otro orden que el manifiesto. La regla aquí es
/// que **todo lo que falte degrade** en lugar de impedir la lectura. Lo único
/// que no se puede perdonar es quedarse sin un solo documento que leer.
class EpubPackage {
  const EpubPackage({
    required this.title,
    required this.author,
    required this.spine,
  });

  /// `null` si el EPUB no lo declara; quien llama pone el nombre del fichero.
  final String? title;
  final String? author;

  /// Los documentos en el orden en que se leen.
  final List<SpineDocument> spine;

  static EpubPackage parse(EpubArchive archive) {
    final opf = archive.readString('/${archive.opfPath}');
    if (opf == null) {
      throw const BookOpenException('El índice de este EPUB no se pudo leer.');
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(opf);
    } on XmlException catch (error) {
      throw BookOpenException(
        'El índice de este EPUB está mal formado.',
        cause: error,
      );
    }

    final manifest = _manifest(document);
    final spineHrefs = _spineHrefs(document, manifest);
    if (spineHrefs.isEmpty) {
      throw const BookOpenException(
        'Este EPUB no declara ni un solo capítulo que leer.',
      );
    }

    final titles = _tocTitles(archive, document, manifest);

    return EpubPackage(
      title: _firstText(document, 'title'),
      author: _firstText(document, 'creator'),
      spine: [
        for (var i = 0; i < spineHrefs.length; i++)
          SpineDocument(
            href: spineHrefs[i].href,
            // Cuando el índice no menciona el documento se numera y ya está.
            // Sacar el título de su `<title>` obligaría a descomprimir el libro
            // entero al abrirlo, y son segundos de espera por un rótulo.
            title: titles[withoutFragment(spineHrefs[i].href)] ??
                'Capítulo ${i + 1}',
            mediaType: spineHrefs[i].mediaType,
          ),
      ],
    );
  }

  /// id → entrada del manifiesto.
  static Map<String, _Item> _manifest(XmlDocument document) {
    final items = <String, _Item>{};
    for (final element in document.findAllElements('item', namespaceUri: '*')) {
      final id = element.getAttribute('id');
      final href = element.getAttribute('href');
      if (id == null || href == null) continue;
      items[id] = _Item(
        href: decodeHref(href),
        mediaType: element.getAttribute('media-type') ?? '',
        properties: element.getAttribute('properties') ?? '',
      );
    }
    return items;
  }

  /// El lomo, en su orden, resuelto contra el manifiesto.
  ///
  /// El orden del lomo **no** tiene por qué coincidir con el del manifiesto, y
  /// de hecho casi nunca coincide: el manifiesto es un inventario y el lomo es
  /// la secuencia de lectura.
  ///
  /// Los documentos con `linear="no"` —notas, cubiertas sueltas— se conservan.
  /// Excluirlos los dejaría inalcanzables, y en un lector sin navegación por
  /// enlaces eso significa perderlos del todo.
  static List<_Item> _spineHrefs(
    XmlDocument document,
    Map<String, _Item> manifest,
  ) {
    final spine = <_Item>[];
    for (final element in document.findAllElements('itemref', namespaceUri: '*')) {
      final idref = element.getAttribute('idref');
      if (idref == null) continue;
      final item = manifest[idref];
      if (item == null) continue;
      spine.add(item);
    }
    return spine;
  }

  /// href (sin fragmento) → título, sacado del índice.
  ///
  /// Se intenta primero el `nav` de EPUB 3 y después el NCX de EPUB 2. Los dos
  /// pueden estar, y en ese caso manda el moderno.
  static Map<String, String> _tocTitles(
    EpubArchive archive,
    XmlDocument document,
    Map<String, _Item> manifest,
  ) {
    final navItem = manifest.values
        .where((item) => item.properties.split(RegExp(r'\s+')).contains('nav'))
        .firstOrNull;
    if (navItem != null) {
      final titles = _navTitles(archive.readString(navItem.href), navItem.href);
      if (titles.isNotEmpty) return titles;
    }

    final tocId = document
        .findAllElements('spine', namespaceUri: '*')
        .firstOrNull
        ?.getAttribute('toc');
    final ncx = tocId == null ? null : manifest[tocId];
    if (ncx != null) {
      return _ncxTitles(archive.readString(ncx.href), ncx.href);
    }

    return const {};
  }

  /// Índice de EPUB 3: un `<nav>` con una lista de enlaces.
  static Map<String, String> _navTitles(String? xhtml, String navHref) {
    if (xhtml == null) return const {};
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xhtml);
    } on XmlException {
      // El documento de navegación es XHTML y debería ser XML válido, pero hay
      // EPUB que lo escriben como HTML suelto. Sin títulos se lee igual.
      return const {};
    }

    final titles = <String, String>{};
    for (final anchor in document.findAllElements('a', namespaceUri: '*')) {
      final href = anchor.getAttribute('href');
      if (href == null) continue;
      final text = _collapse(anchor.innerText);
      if (text.isEmpty) continue;
      // Los href del índice son relativos al propio índice, no al OPF.
      titles.putIfAbsent(resolveHref(navHref, href), () => text);
    }
    return titles;
  }

  /// Índice de EPUB 2: el NCX, con sus `navPoint` anidados.
  static Map<String, String> _ncxTitles(String? ncx, String ncxHref) {
    if (ncx == null) return const {};
    final XmlDocument document;
    try {
      document = XmlDocument.parse(ncx);
    } on XmlException {
      return const {};
    }

    final titles = <String, String>{};
    // `findAllElements` recorre en orden de documento, así que los navPoint
    // anidados salen ya aplanados y en el orden correcto.
    for (final point in document.findAllElements('navPoint', namespaceUri: '*')) {
      final src = point
          .findElements('content', namespaceUri: '*')
          .firstOrNull
          ?.getAttribute('src');
      if (src == null) continue;
      final label = point
          .findAllElements('text', namespaceUri: '*')
          .firstOrNull
          ?.innerText;
      final text = _collapse(label ?? '');
      if (text.isEmpty) continue;
      titles.putIfAbsent(resolveHref(ncxHref, src), () => text);
    }
    return titles;
  }

  /// Un `dc:title` o `dc:creator`, el primero que haya.
  static String? _firstText(XmlDocument document, String name) {
    final element = document
        .findAllElements(name, namespaceUri: '*')
        .firstOrNull;
    final text = _collapse(element?.innerText ?? '');
    return text.isEmpty ? null : text;
  }

  static String _collapse(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _Item {
  const _Item({
    required this.href,
    required this.mediaType,
    required this.properties,
  });

  final String href;
  final String mediaType;
  final String properties;
}
