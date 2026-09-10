# -*- coding: utf-8 -*-
"""SVG dosyalarındaki <style> bloğunu sunum özniteliklerine gömer.

Bazı taş takımları biçimlendirmeyi CSS sınıflarıyla verir:

    <style>.base{fill-rule:evenodd}.stroke-color{stroke:#000}</style>
    <path class="base stroke-color" d="..."/>

`flutter_svg` <style> öğesini desteklemez; bu dosyalar olduğu gibi
kullanılırsa konturlar ve dolgu kuralları sessizce kaybolur, taşlar
düz siluete döner.

Bu betik sınıf kurallarını çözüp her öğeye doğrudan öznitelik olarak
yazar ve <style> ile class niteliklerini kaldırır. CSS öncelik sırası
korunur:

    sunum özniteliği  <  sınıf kuralı  <  satır içi style

Kullanımı:

    python tools/assets/inline_svg_styles.py assets/pieces
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

SVG_NS = 'http://www.w3.org/2000/svg'
XLINK_NS = 'http://www.w3.org/1999/xlink'

# Sınıf kurallarından gelebilecek, SVG'de aynı adla sunum özniteliği olan
# özellikler. Listede olmayan bir özellik sessizce atlanır ki geçersiz
# öznitelik üretmeyelim.
PRESENTATION = {
    'fill', 'fill-opacity', 'fill-rule',
    'stroke', 'stroke-width', 'stroke-opacity', 'stroke-linecap',
    'stroke-linejoin', 'stroke-miterlimit', 'stroke-dasharray',
    'stroke-dashoffset',
    'opacity', 'color', 'display', 'visibility', 'paint-order',
}

RULE = re.compile(r'\.([A-Za-z0-9_-]+)\s*\{([^}]*)\}')


def parse_declarations(text):
    out = {}
    for part in text.split(';'):
        if ':' not in part:
            continue
        name, _, value = part.partition(':')
        name = name.strip()
        value = value.strip()
        if name and value:
            out[name] = value
    return out


def parse_stylesheet(text):
    """`.sinif{...}` kurallarını sırayla döndürür."""
    rules = []
    for name, body in RULE.findall(text):
        rules.append((name, parse_declarations(body)))
    return rules


def strip_ns(tag):
    return tag.split('}', 1)[1] if '}' in tag else tag


def inline(path):
    ET.register_namespace('', SVG_NS)
    ET.register_namespace('xlink', XLINK_NS)
    tree = ET.parse(path)
    root = tree.getroot()

    # <style> içeriğini topla ve öğeleri kaldır.
    rules = []
    for parent in root.iter():
        for child in list(parent):
            if strip_ns(child.tag) == 'style':
                rules.extend(parse_stylesheet(child.text or ''))
                parent.remove(child)
    if not rules:
        return False

    by_class = {}
    for name, decls in rules:
        by_class.setdefault(name, {}).update(decls)

    changed = False
    for el in root.iter():
        classes = el.get('class')
        if not classes:
            continue
        # Öncelik: sunum özniteliği < sınıf < satır içi style
        props = {}
        for name in classes.split():
            props.update(by_class.get(name, {}))
        inline_style = parse_declarations(el.get('style', ''))
        props.update(inline_style)

        for name, value in props.items():
            if name in PRESENTATION:
                el.set(name, value)
        del el.attrib['class']
        if 'style' in el.attrib:
            del el.attrib['style']
        changed = True

    if changed:
        tree.write(path, encoding='utf-8', xml_declaration=False)
    return changed


def main(root_dir):
    touched = 0
    for folder, _, files in os.walk(root_dir):
        for name in sorted(files):
            if not name.endswith('.svg'):
                continue
            if inline(os.path.join(folder, name)):
                touched += 1
    print('%d dosyada stil gömüldü' % touched)


if __name__ == '__main__':
    main(sys.argv[1])
