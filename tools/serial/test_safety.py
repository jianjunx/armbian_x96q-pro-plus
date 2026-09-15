"""Offline regressions; never imports pyserial or touches a device."""
import ast
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SafetyTests(unittest.TestCase):
    @unittest.skipUnless(os.sys.platform.startswith("linux") and shutil.which("rsync"),
                         "Run on Linux with target rsync (macOS openrsync differs)")
    def test_copy_verifier_checks_links_and_file_content(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, dst = Path(tmp, "src"), Path(tmp, "dst")
            src.mkdir()
            dst.mkdir()
            for directory in (src, dst):
                (directory / "extramodules").symlink_to("../missing-extramodules")
                (directory / "module.ko").write_bytes(b"test module")
            def differences():
                return subprocess.run(
                    ["rsync", "-rlcni", "--out-format=%i %n%L", str(src)+"/", str(dst)+"/"],
                    capture_output=True, text=True, check=True,
                ).stdout
            self.assertEqual(differences(), "")
            (dst / "extramodules").unlink()
            (dst / "extramodules").symlink_to("../wrong-target")
            self.assertIn("extramodules", differences())
            (dst / "extramodules").unlink()
            (dst / "extramodules").symlink_to("../missing-extramodules")
            (dst / "module.ko").write_bytes(b"bad! module")
            self.assertIn("module.ko", differences())
        script = (ROOT / "revision-v3.1/h728-install-emmc").read_text()
        self.assertNotIn("rsync -rcn", script)
        self.assertEqual(script.count("rsync -rlcni"), 2)

    def test_retired_writers_fail_before_serial_access(self):
        for name in ("h728_flash_emmc_uboot.py", "h728_emmc_one_pass.py"):
            result = subprocess.run(
                [os.sys.executable, str(ROOT / "tools/serial" / name),
                 "NOT_A_REAL_PORT", "payload.bin"],
                env={**os.environ, "H728_QUICK": "1"},
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("No serial port was opened", result.stderr)

    def test_no_literal_password_write(self):
        tree = ast.parse((ROOT / "tools/serial/h728_serial_shell.py").read_text())
        literals = []
        for node in ast.walk(tree):
            if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                    and node.func.attr == "write" and node.args
                    and isinstance(node.args[0], ast.Constant)):
                literals.append(node.args[0].value)
        self.assertEqual(set(literals), {b"\n", b"root\n", b"echo __PROBE__\n"})
        self.assertIn("getpass.getpass", ast.unparse(tree))

    def test_config_checker_rejects_missing_and_multiblock_config(self):
        script = ROOT / "revision-v3/configure-emmc-uboot.sh"
        good = ('CONFIG_MMC_SUNXI_SLOT_EXTRA=2\n'
                'CONFIG_SYS_MMC_MAX_BLK_COUNT=1\n'
                'CONFIG_OF_LIBFDT_OVERLAY=y\n'
                'CONFIG_IDENT_STRING=" H728 eMMC v3"\n')
        with tempfile.TemporaryDirectory() as tmp:
            for config, valid in (("", False), (good, True),
                                  (good.replace("BLK_COUNT=1", "BLK_COUNT=64"), False)):
                Path(tmp, ".config").write_text(config)
                result = subprocess.run(["bash", str(script), "check"], cwd=tmp,
                                        capture_output=True, check=False)
                self.assertEqual(result.returncode == 0, valid)

    def test_all_builders_use_shared_configuration(self):
        for name in ("revision-v3/build-emmc-uboot.sh",
                     "ci/build-uboot-emmc-container.sh", ".github/workflows/uboot-emmc.yml"):
            text = (ROOT / name).read_text()
            self.assertIn("configure-emmc-uboot.sh", text)
            self.assertNotIn("scripts/config --set-val CONFIG_SYS_MMC_MAX_BLK_COUNT", text)
            self.assertNotIn("scripts/config --set-val MMC_SUNXI_SLOT_EXTRA", text)

    def test_installer_safety_structure_without_execution(self):
        text = (ROOT / "revision-v3.1/h728-install-emmc").read_text()
        for required in ('mode=${1:---check}', 'NO BACKUP ERASE', 'assert_target',
                         'flock -n 9', 'iflag=direct', 'fsck.vfat -n',
                         'e2fsck -fn', 'cmp -n "$blob_size"',
                         'h728-check-emmc-payload', 'backup_source='):
            self.assertIn(required, text)
        self.assertLess(text.index('read -r answer'), text.index('wipefs --all'))
        self.assertLess(text.index('[[ $answer == "$token" ]]'), text.index('wipefs --all'))
        self.assertLess(text.index('Boot copy differs'), text.index('of="$target"'))
        self.assertNotIn('mmc bootpart', text)
        self.assertNotIn('mmc partconf', text)
        verify = (ROOT / "revision-v3.1/verify.sh").read_text()
        self.assertNotIn('h728-install-emmc --install', verify)


if __name__ == "__main__":
    unittest.main()
