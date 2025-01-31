#! /usr/bin/python3
#
# Python 3 script to preprocess .html files below htdocs

import re
import sys

input_path = sys.argv[1]
output_path = sys.argv[2]

with open(input_path) as f_in:
    with open(output_path, 'w') as f_out:
        for line in f_in:
            # Convert from e.g.
            #   <h1 id="ID">TEXT</h1>
            # to:
            #   <h1 id="ID"><a href="#ID">TEXT</a></h1>
            for element_name in {'h1', 'h2', 'h3', 'h4'}:
                pattern = \
                    (r'<'
                     + element_name
                     + r' id="(.+)">(.+)</'
                     + element_name
                     + '>')
                replacement = \
                    (r'<'
                     + element_name
                     + r' id="\1"><a href="#\1">\2</a></'
                     + element_name
                     + '>')
                line = re.sub(pattern, replacement, line)
            f_out.write(line)
