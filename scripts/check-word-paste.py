#!/usr/bin/env python
"""Verify the document saved by the optional real-Word paste integration check."""
import sys
from zipfile import ZipFile
import xml.etree.ElementTree as ET

ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
w = '{' + ns['w'] + '}'
with ZipFile(sys.argv[1]) as archive:
    document = ET.fromstring(archive.read('word/document.xml'))
    styles = ET.fromstring(archive.read('word/styles.xml'))
    relationships = ET.fromstring(archive.read('word/_rels/document.xml.rels'))


def check(condition, label):
    if not condition:
        raise AssertionError(label)
    print('PASS', label)


paragraphs = document.findall('.//w:p', ns)
def paragraph(text):
    return next(p for p in paragraphs if ''.join(p.itertext()) == text)

check(paragraph('Reader checks').find('w:pPr/w:pStyle', ns).get(w+'val') == 'Heading1', 'real Word heading style')
tables = document.findall('.//w:tbl', ns)
check(len(tables) == 1 and len(tables[0].findall('.//w:tc', ns)) == 6, 'real editable Word table, six cells')
check(all(cell.find('w:tcPr/w:tcBorders', ns) is not None for cell in tables[0].findall('.//w:tc', ns)), 'borders on every Word table cell')
check(paragraph('123').find('w:pPr/w:jc', ns).get(w+'val') == 'right' and paragraph('c').find('w:pPr/w:jc', ns).get(w+'val') == 'center', 'right and centre column alignment')
check(paragraph('    first_line = 1') is not None and paragraph('    second_line = 2') is not None, 'code indentation preserved on both lines')
code_style = next(s for s in styles.findall('w:style', ns) if s.get(w+'styleId') == 'HTMLCode')
check(code_style.find('w:rPr/w:rFonts', ns).get(w+'ascii') == 'Courier New', 'monospace Word code style')
targets = [r.get('Target') for r in relationships if r.get('Type', '').endswith('/hyperlink')]
check(any(t.startswith('file:///') and 'other%20file.markdown' in t for t in targets) and 'https://example.com/' in targets, 'absolute local and external link targets')
check(''.join(document.itertext()).count('$E=mc^2$') == 1, 'formula source once, unchanged fallback')
print('RESULT 8/8 Word document checks passed')
