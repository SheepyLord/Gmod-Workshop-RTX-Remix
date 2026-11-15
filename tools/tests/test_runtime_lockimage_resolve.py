"""A read-back resolves only a multisampled image (runtime patch 0097, GitHub issue 12).

`D3D9DeviceEx::LockImage` chose the image a read-back copies from with
`sampleCount != 1 ? pResource->GetResolveImage() : std::move(resourceImage)` and resolved whenever `resourceImage` was
still set. MSVC never moves there (the conditional binds the resolve image's const reference), so every read-back of a
single-sample image resolved the image into itself: `vkCmdResolveImage` with one sample and the same image on both
sides, which AMD's driver crashes on. Compiles the lines the patch removes and the lines it adds with MSVC, as the
runtime builds them (`/std:c++latest`), against stand-ins for DXVK's `Rc`, `DxvkImage` and `D3D9CommonTexture`:
the old lines resolve a single-sample image, the new ones only a multisampled one."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
PATCHES = sorted((REPO / 'runtime' / 'patches').glob('0097-*.patch'))
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
DEVICE = 'src/d3d9/d3d9_device.cpp'
MARK = '// NV-DXVK start: only a multisampled image is resolved'


def patch_text() -> str:
    if len(PATCHES) != 1:
        raise AssertionError(f'expected one runtime patch 0097, found {[p.name for p in PATCHES]}')
    return PATCHES[0].read_text(encoding='utf-8')


def file_block(patch: str, path: str) -> str:
    # Up to the next file's diff, or to format-patch's signature ("-- " and the git version) after the last one.
    return patch.split(f'diff --git a/{path} b/{path}\n', 1)[1].split('\ndiff --git ', 1)[0].split('\n-- \n', 1)[0]


def changed(patch: str, sign: str) -> list[str]:
    """The lines of LockImage's hunk the patch removes ('-') or adds ('+'), without the sign."""
    body = file_block(patch, DEVICE).split('\n@@', 1)[1]
    return [line[1:].rstrip('\r') for line in body.splitlines()[1:]
            if line.startswith(sign) and not line.startswith(sign * 3)]


HARNESS = r'''#include <cstddef>
#include <cstdio>
#include <utility>

#define unlikely(x) (x)
enum VkSampleCountFlagBits { VK_SAMPLE_COUNT_1_BIT = 1, VK_SAMPLE_COUNT_4_BIT = 4 };
struct DxvkImageCreateInfo { VkSampleCountFlagBits sampleCount; };

struct DxvkImage {
  DxvkImageCreateInfo m_info;
  int m_refs = 0;
  const DxvkImageCreateInfo& info() const { return m_info; }
};

// DXVK's Rc (src/util/rc/util_rc_ptr.h), reduced: the copy takes a reference, the move takes the pointer.
template <typename T>
class Rc {
public:
  Rc() { }
  Rc(std::nullptr_t) { }
  Rc(T* object) : m_object(object) { inc(); }
  Rc(const Rc& other) : m_object(other.m_object) { inc(); }
  Rc(Rc&& other) : m_object(other.m_object) { other.m_object = nullptr; }
  ~Rc() { dec(); }
  Rc& operator = (std::nullptr_t) { dec(); m_object = nullptr; return *this; }
  Rc& operator = (const Rc& other) { other.inc(); dec(); m_object = other.m_object; return *this; }
  Rc& operator = (Rc&& other) { dec(); m_object = other.m_object; other.m_object = nullptr; return *this; }
  T* operator -> () const { return m_object; }
  T* ptr() const { return m_object; }
  bool operator == (std::nullptr_t) const { return m_object == nullptr; }
  bool operator != (std::nullptr_t) const { return m_object != nullptr; }
private:
  T* m_object = nullptr;
  void inc() const { if (m_object) m_object->m_refs += 1; }
  void dec() const { if (m_object) m_object->m_refs -= 1; }
};

struct D3D9CommonTexture {
  Rc<DxvkImage> m_image;
  Rc<DxvkImage> m_resolveImage;
  const Rc<DxvkImage>& GetImage() const { return m_image; }
  const Rc<DxvkImage>& GetResolveImage() { return m_resolveImage; }
};

// LockImage's choice: `resolves` when its `if (resourceImage != nullptr)` emits the resolve, `mapped` the image the
// read-back then copies into the buffer.
struct Choice { bool resolves; DxvkImage* mapped; };

static Choice before(D3D9CommonTexture* pResource) {
  Rc<DxvkImage> resourceImage = pResource->GetImage();
@@BEFORE@@
  return { resourceImage != nullptr, mappedImage.ptr() };
}

static Choice after(D3D9CommonTexture* pResource) {
  Rc<DxvkImage> resourceImage = pResource->GetImage();
@@AFTER@@
  return { resourceImage != nullptr, mappedImage.ptr() };
}

static int checks = 0;
static int failures = 0;

static void check(bool ok, const char* what) {
  checks += 1;
  if (!ok) {
    failures += 1;
    std::printf("FAIL %s\n", what);
  }
}

int main() {
  DxvkImage single { { VK_SAMPLE_COUNT_1_BIT } };
  DxvkImage multi { { VK_SAMPLE_COUNT_4_BIT } };
  DxvkImage resolved { { VK_SAMPLE_COUNT_1_BIT } };
  {
    D3D9CommonTexture plain { Rc<DxvkImage>(&single), nullptr };
    D3D9CommonTexture msaa { Rc<DxvkImage>(&multi), Rc<DxvkImage>(&resolved) };

    // The bug under the runtime's compiler: the old lines resolve a single-sample image into itself.
    const Choice old = before(&plain);
    check(old.resolves && old.mapped == &single, "the old lines resolve a single-sample image into itself (MSVC)");
    const Choice oldMsaa = before(&msaa);
    check(oldMsaa.resolves && oldMsaa.mapped == &resolved, "the old lines resolve a multisampled image");

    const Choice plainNow = after(&plain);
    check(!plainNow.resolves, "a single-sample image is not resolved");
    check(plainNow.mapped == &single, "a single-sample image is read back from itself");
    const Choice msaaNow = after(&msaa);
    check(msaaNow.resolves, "a multisampled image is resolved");
    check(msaaNow.mapped == &resolved, "a multisampled image is read back from its resolve image");
    check(single.m_refs == 1 && multi.m_refs == 1 && resolved.m_refs == 1, "no reference is kept or lost");
  }
  check(single.m_refs == 0 && multi.m_refs == 0 && resolved.m_refs == 0, "every reference is released");
  if (failures != 0)
    return 1;
  std::printf("PASS lockimage resolve: %d checks\n", checks);
  return 0;
}
'''

SCRIPT = '''param([string]$Repo, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++latest /O2 /W4 /WX /utf-8 lockimage.cpp /Felockimage.exe /Folockimage.obj
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& ./lockimage.exe
exit $LASTEXITCODE
'''


class LockImageResolveTests(unittest.TestCase):
    def test_the_patch_changes_only_lockimages_choice(self):
        patch = patch_text()
        self.assertEqual(patch.count('diff --git '), 1, 'the patch changes one file')
        self.assertIn(f'diff --git a/{DEVICE} b/{DEVICE}', patch)
        removed, added = changed(patch, '-'), changed(patch, '+')
        self.assertEqual([line.strip() for line in removed],
                         ['Rc<DxvkImage> mappedImage = resourceImage->info().sampleCount != 1',
                          '? pResource->GetResolveImage()', ': std::move(resourceImage);'])
        self.assertEqual(added[0].strip(), MARK + ' (GMod issue 12)')
        self.assertEqual(added[-1].strip(), '// NV-DXVK end')
        code = [line.strip() for line in added if not line.strip().startswith('//')]
        self.assertEqual(code, ['Rc<DxvkImage> mappedImage;',
                                'if (resourceImage->info().sampleCount != VK_SAMPLE_COUNT_1_BIT)',
                                'mappedImage = pResource->GetResolveImage();', 'else',
                                'mappedImage = std::move(resourceImage);'])
        # The resolve itself is left as it is (outside the hunk): it still runs while resourceImage is set, which is
        # now only a multisampled image.
        self.assertNotIn('resourceImage != nullptr', '\n'.join(removed + added))

    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_only_a_multisampled_image_is_resolved(self):
        patch = patch_text()
        source = (HARNESS.replace('@@BEFORE@@', '\n'.join(changed(patch, '-')))
                  .replace('@@AFTER@@', '\n'.join(changed(patch, '+'))))
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='lockimage-', dir=scratch) as directory:
            root = Path(directory)
            (root / 'lockimage.cpp').write_text(source, encoding='utf-8')
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=300)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertRegex(result.stdout, r'PASS lockimage resolve: \d+ checks')


if __name__ == '__main__':
    unittest.main()
