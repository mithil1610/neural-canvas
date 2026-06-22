import os
import re

lib_dir = r'c:\Users\Mithil\OneDrive\Documents\neural_canvas\lib'

for root, _, files in os.walk(lib_dir):
    for f in files:
        if f.endswith('.dart'):
            path = os.path.join(root, f)
            with open(path, 'r', encoding='utf-8') as file:
                content = file.read()
            
            # replace `debugPrint(` with `if (kDebugMode) debugPrint(`
            new_content = re.sub(r'(?<!if \(kDebugMode\) )\bdebugPrint\(', r'if (kDebugMode) debugPrint(', content)
            
            if new_content != content:
                # Add import if missing
                if 'import \'package:flutter/foundation.dart\';' not in new_content:
                    if 'import \'package:flutter/foundation.dart\' show kIsWeb;' in new_content:
                         new_content = new_content.replace('import \'package:flutter/foundation.dart\' show kIsWeb;', 'import \'package:flutter/foundation.dart\';')
                    else:
                         new_content = "import 'package:flutter/foundation.dart';\n" + new_content
                with open(path, 'w', encoding='utf-8') as file:
                    file.write(new_content)
                print(f"Updated {path}")
