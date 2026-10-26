import sys
path = sys.argv[1]
s = open(path, encoding='utf-8').read()
if '无需 LibreOfficeKit' in s:
    print('  ⏭ 已含降级'); raise SystemExit(0)
a = "  try {\n    const result = await renderOfficeTemplatePreview("
b = "    console.log('Packaged isolated template import and Office preview passed')\n  } finally {"
if a not in s or b not in s:
    print('  ⚠ 锚点未匹配，可能上游已改'); raise SystemExit(0)
s = s.replace(a, "  try {\n    // Linux 上没有官方 LibreOfficeKit 包，模板预览渲染用不了；只跳过这段校验。\n    try {\n    const result = await renderOfficeTemplatePreview(", 1)
s = s.replace(b, """    console.log('Packaged isolated template import and Office preview passed')
    } catch (error) {
      const detail = `${error?.message ?? ''} ${error?.cause?.message ?? ''}`
      if (process.platform !== 'linux' || !/libreoffice-kit-linux/u.test(detail)) throw error
      console.warn('[build] Linux 无需 LibreOfficeKit 的模板预览不可用，跳过该校验')
    }
  } finally {""", 1)
open(path, 'w', encoding='utf-8').write(s)
print('  ✅ verify-packaged-ppt-runtime.cjs: 模板预览在 Linux 上可跳过')
