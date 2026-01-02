#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch


class TestKokoroVoices(unittest.TestCase):
    def setUp(self):
        self.original_argv = sys.argv
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        sys.argv = self.original_argv
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    @patch.dict("sys.modules", {"huggingface_hub": MagicMock()})
    def test_filters_voice_file_extensions(self):
        from huggingface_hub import snapshot_download

        voices_dir = os.path.join(self.temp_dir, "voices")
        os.makedirs(voices_dir)
        for f in ["af_heart.pt", "bf_emma.onnx", "readme.txt", "config.json"]:
            open(os.path.join(voices_dir, f), "w").close()

        snapshot_download.return_value = self.temp_dir
        sys.argv = ["kokoro_voices.py", "--all"]

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_voices", os.path.join(os.path.dirname(__file__), "kokoro_voices.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with patch("builtins.print") as mock_print:
            result = module.main()

        self.assertEqual(result, 0)
        voices = json.loads(mock_print.call_args[0][0])
        self.assertEqual(sorted(voices), ["af_heart", "bf_emma"])


class TestKokoroListRemote(unittest.TestCase):
    def setUp(self):
        self.original_argv = sys.argv
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        sys.argv = self.original_argv
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_is_voice_file(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_list_remote", os.path.join(os.path.dirname(__file__), "kokoro_list_remote.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        self.assertTrue(module.is_voice_file("voice.pt"))
        self.assertTrue(module.is_voice_file("voice.onnx"))
        self.assertTrue(module.is_voice_file("voice.bin"))
        self.assertFalse(module.is_voice_file("config.json"))
        self.assertFalse(module.is_voice_file("readme.txt"))

    def test_get_voice_name_from_path(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_list_remote", os.path.join(os.path.dirname(__file__), "kokoro_list_remote.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        self.assertEqual(module.get_voice_name_from_path("voices/af_heart.pt"), "af_heart")
        self.assertEqual(module.get_voice_name_from_path("/path/to/bf_emma.onnx"), "bf_emma")


if __name__ == "__main__":
    unittest.main()
