#!/usr/bin/python3
#
# Copyright (C) 2018 Free Software Foundation, Inc.
#
# Contributed by David Malcolm
#
# GCC is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 3, or (at your option) any later
# version.
#
# GCC is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License
# along with GCC; see the file COPYING3.  If not see
# <http://www.gnu.org/licenses/>.

import html
import re
import sys
import unittest

# Colors from gcc/color-macros.h:

COLOR_SEPARATOR  = ";"
COLOR_NONE       = "00"
COLOR_BOLD       = "01"
COLOR_UNDERSCORE = "04"
COLOR_BLINK      = "05"
COLOR_REVERSE    = "07"
COLOR_FG_BLACK   = "30"
COLOR_FG_RED     = "31"
COLOR_FG_GREEN   = "32"
COLOR_FG_YELLOW  = "33"
COLOR_FG_BLUE    = "34"
COLOR_FG_MAGENTA = "35"
COLOR_FG_CYAN    = "36"
COLOR_FG_WHITE   = "37"
COLOR_BG_BLACK   = "40"
COLOR_BG_RED     = "41"
COLOR_BG_GREEN   = "42"
COLOR_BG_YELLOW  = "43"
COLOR_BG_BLUE    = "44"
COLOR_BG_MAGENTA = "45"
COLOR_BG_CYAN    = "46"
COLOR_BG_WHITE   = "47"

SGR_START = "\33["
SGR_END   = "m\33[K"

def SGR_SEQ(str):
    return SGR_START + str + SGR_END

SGR_RESET = SGR_SEQ("")

def ansi_to_html(text):
    text = html.escape(text)
    pattern = ('(' + re.escape(SGR_START) + ')'
               + '(.*?)'
               + '(' + re.escape(SGR_END) + ')')
    while True:
        m = re.search(pattern, text)
        if not m:
            break
        sgr_seq = m.group(2)
        if sgr_seq == COLOR_BOLD:
            replacement = '<span class="bold">'
        elif sgr_seq == COLOR_FG_RED:
            replacement = '<span class="red">'
        elif sgr_seq == COLOR_FG_GREEN:
            replacement = '<span class="green">'
        elif sgr_seq == COLOR_FG_BLUE:
            replacement = '<span class="blue">'
        elif sgr_seq == '':
            replacement = '</span>'
        elif sgr_seq == COLOR_BOLD + COLOR_SEPARATOR + COLOR_FG_RED:
            replacement = '<span class="boldred">'
        elif sgr_seq == COLOR_BOLD + COLOR_SEPARATOR + COLOR_FG_GREEN:
            replacement = '<span class="boldgreen">'
        elif sgr_seq == COLOR_BOLD + COLOR_SEPARATOR + COLOR_FG_CYAN:
            replacement = '<span class="boldcyan">'
        elif sgr_seq == COLOR_BOLD + COLOR_SEPARATOR + COLOR_FG_MAGENTA:
            replacement = '<span class="boldmagenta">'
        else:
            raise ValueError('unknown SGR_SEQ code: %r' % sgr_seq)
        text = text[:m.start(1)] + replacement + text[m.end(3):]
    return text

class AnsiToHtmlTests(unittest.TestCase):
    def assert_html(self, ansi_text, expected_html):
        html = ansi_to_html(ansi_text)
        self.assertMultiLineEqual(html, expected_html)

    def test_simple(self):
        self.assert_html('', '')
        self.assert_html('plain text', 'plain text')

    def test_filename(self):
        self.assert_html("\x1b[01m\x1b[Kfilename.c:\x1b[m\x1b[K In function '\x1b[01m\x1b[Ktest\x1b[m\x1b[K':\n",
                         '<span class="bold">filename.c:</span> In function &#x27;<span class="bold">test</span>&#x27;:\n')

    def test_error(self):
        self.assert_html("\x1b[01;31m\x1b[Kerror: \x1b[m\x1b[K'\x1b[01m\x1b[KNULL\x1b[m\x1b[K' undeclared",
                         '<span class="boldred">error: </span>&#x27;<span class="bold">NULL</span>&#x27; undeclared')

    def test_escaping(self):
        self.assert_html("#include <stdio.h>", "#include &lt;stdio.h&gt;")

if len(sys.argv) > 1:
    sys.exit(unittest.main())

for line in sys.stdin:
    line = ansi_to_html(line)
    sys.stdout.write(line)
