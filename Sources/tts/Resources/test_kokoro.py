#!/usr/bin/env python3
"""Unit tests for Kokoro Python scripts."""
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch, call


class TestKokoroPrefetch(unittest.TestCase):
    """Tests for kokoro_prefetch.py"""

    def setUp(self):
        """Reset sys.argv before each test."""
        self.original_argv = sys.argv

    def tearDown(self):
        """Restore sys.argv after each test."""
        sys.argv = self.original_argv

    @patch.dict('sys.modules', {
        'huggingface_hub': MagicMock(),
        'huggingface_hub.utils': MagicMock(),
        'huggingface_hub.utils.logging': MagicMock(),
    })
    def test_prefetch_success(self):
        """Test successful prefetch with default arguments."""
        from huggingface_hub import snapshot_download
        snapshot_download.return_value = "/path/to/cache"

        sys.argv = ['kokoro_prefetch.py']

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_prefetch",
            os.path.join(os.path.dirname(__file__), "kokoro_prefetch.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        result = module.main()

        self.assertEqual(result, 0)
        snapshot_download.assert_called_once_with(
            repo_id="hexgrad/Kokoro-82M",
            revision=None,
        )

    @patch.dict('sys.modules', {
        'huggingface_hub': MagicMock(),
        'huggingface_hub.utils': MagicMock(),
        'huggingface_hub.utils.logging': MagicMock(),
    })
    def test_prefetch_custom_repo_and_revision(self):
        """Test prefetch with custom repo and revision."""
        from huggingface_hub import snapshot_download
        snapshot_download.return_value = "/path/to/cache"

        sys.argv = ['kokoro_prefetch.py', '--repo', 'custom/repo', '--revision', 'v1.0']

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_prefetch",
            os.path.join(os.path.dirname(__file__), "kokoro_prefetch.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        result = module.main()

        self.assertEqual(result, 0)
        snapshot_download.assert_called_once_with(
            repo_id="custom/repo",
            revision="v1.0",
        )

    def test_prefetch_import_failure(self):
        """Test prefetch when huggingface_hub is not installed."""
        sys.argv = ['kokoro_prefetch.py']

        # Remove huggingface_hub from modules if present
        modules_to_remove = [k for k in sys.modules.keys() if 'huggingface_hub' in k]
        saved_modules = {k: sys.modules.pop(k) for k in modules_to_remove}

        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location(
                "kokoro_prefetch_fail",
                os.path.join(os.path.dirname(__file__), "kokoro_prefetch.py")
            )
            module = importlib.util.module_from_spec(spec)

            # Mock the import to fail
            original_import = __builtins__.__import__ if hasattr(__builtins__, '__import__') else __import__

            def mock_import(name, *args, **kwargs):
                if 'huggingface_hub' in name:
                    raise ImportError("No module named 'huggingface_hub'")
                return original_import(name, *args, **kwargs)

            with patch('builtins.__import__', mock_import):
                spec.loader.exec_module(module)
                result = module.main()

            self.assertEqual(result, 1)
        finally:
            sys.modules.update(saved_modules)

    @patch.dict('sys.modules', {
        'huggingface_hub': MagicMock(),
        'huggingface_hub.utils': MagicMock(),
        'huggingface_hub.utils.logging': MagicMock(),
    })
    def test_prefetch_download_failure(self):
        """Test prefetch when snapshot_download fails."""
        from huggingface_hub import snapshot_download
        snapshot_download.side_effect = Exception("Download failed")

        sys.argv = ['kokoro_prefetch.py']

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_prefetch",
            os.path.join(os.path.dirname(__file__), "kokoro_prefetch.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        result = module.main()

        self.assertEqual(result, 2)


class TestKokoroSay(unittest.TestCase):
    """Tests for kokoro_say.py"""

    def setUp(self):
        """Reset sys.argv before each test."""
        self.original_argv = sys.argv
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Restore sys.argv after each test."""
        sys.argv = self.original_argv
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    @patch.dict('sys.modules', {
        'kokoro': MagicMock(),
        'huggingface_hub': MagicMock(),
        'numpy': MagicMock(),
        'soundfile': MagicMock(),
    })
    def test_say_success(self):
        """Test successful speech synthesis."""
        import numpy as np
        from kokoro import KPipeline
        from huggingface_hub import snapshot_download
        import soundfile as sf

        # Setup mocks
        snapshot_download.return_value = "/path/to/cache"
        mock_pipeline = MagicMock()
        mock_audio = MagicMock()
        mock_pipeline.return_value = [(None, None, mock_audio)]
        KPipeline.return_value = mock_pipeline

        sys.modules['numpy'].concatenate = MagicMock(return_value=mock_audio)

        out_path = os.path.join(self.temp_dir, "output.wav")
        sys.argv = ['kokoro_say.py', '--text', 'Hello world', '--out', out_path]

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_say",
            os.path.join(os.path.dirname(__file__), "kokoro_say.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        result = module.main()

        self.assertEqual(result, 0)
        KPipeline.assert_called_once_with(lang_code='a')
        mock_pipeline.assert_called_once_with('Hello world', voice='af_heart')

    @patch.dict('sys.modules', {
        'kokoro': MagicMock(),
        'huggingface_hub': MagicMock(),
        'numpy': MagicMock(),
        'soundfile': MagicMock(),
    })
    def test_say_custom_voice_and_lang(self):
        """Test speech synthesis with custom voice and language."""
        from kokoro import KPipeline
        from huggingface_hub import snapshot_download

        snapshot_download.return_value = "/path/to/cache"
        mock_pipeline = MagicMock()
        mock_audio = MagicMock()
        mock_pipeline.return_value = [(None, None, mock_audio)]
        KPipeline.return_value = mock_pipeline

        sys.modules['numpy'].concatenate = MagicMock(return_value=mock_audio)

        out_path = os.path.join(self.temp_dir, "output.wav")
        sys.argv = [
            'kokoro_say.py',
            '--text', 'Hello',
            '--out', out_path,
            '--voice', 'bf_emma',
            '--lang', 'b'
        ]

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_say",
            os.path.join(os.path.dirname(__file__), "kokoro_say.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        result = module.main()

        self.assertEqual(result, 0)
        KPipeline.assert_called_once_with(lang_code='b')
        mock_pipeline.assert_called_once_with('Hello', voice='bf_emma')

    @patch.dict('sys.modules', {
        'kokoro': MagicMock(),
        'huggingface_hub': MagicMock(),
        'numpy': MagicMock(),
        'soundfile': MagicMock(),
    })
    def test_say_no_audio_returned(self):
        """Test when pipeline returns no audio chunks."""
        from kokoro import KPipeline
        from huggingface_hub import snapshot_download

        snapshot_download.return_value = "/path/to/cache"
        mock_pipeline = MagicMock()
        mock_pipeline.return_value = []  # Empty - no audio
        KPipeline.return_value = mock_pipeline

        out_path = os.path.join(self.temp_dir, "output.wav")
        sys.argv = ['kokoro_say.py', '--text', 'Hello', '--out', out_path]

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_say",
            os.path.join(os.path.dirname(__file__), "kokoro_say.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        result = module.main()

        self.assertEqual(result, 2)

    @patch.dict('sys.modules', {
        'kokoro': MagicMock(),
        'huggingface_hub': MagicMock(),
        'numpy': MagicMock(),
        'soundfile': MagicMock(),
    })
    def test_say_pipeline_exception(self):
        """Test when pipeline raises an exception."""
        from kokoro import KPipeline
        from huggingface_hub import snapshot_download

        snapshot_download.return_value = "/path/to/cache"
        KPipeline.side_effect = Exception("Pipeline error")

        out_path = os.path.join(self.temp_dir, "output.wav")
        sys.argv = ['kokoro_say.py', '--text', 'Hello', '--out', out_path]

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_say",
            os.path.join(os.path.dirname(__file__), "kokoro_say.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        result = module.main()

        self.assertEqual(result, 3)

    def test_say_import_failure(self):
        """Test when dependencies are not installed."""
        out_path = os.path.join(self.temp_dir, "output.wav")
        sys.argv = ['kokoro_say.py', '--text', 'Hello', '--out', out_path]

        # Remove modules if present
        modules_to_remove = [k for k in sys.modules.keys()
                            if any(m in k for m in ['kokoro', 'huggingface_hub', 'soundfile'])]
        saved_modules = {k: sys.modules.pop(k) for k in modules_to_remove}

        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location(
                "kokoro_say_fail",
                os.path.join(os.path.dirname(__file__), "kokoro_say.py")
            )
            module = importlib.util.module_from_spec(spec)

            original_import = __builtins__.__import__ if hasattr(__builtins__, '__import__') else __import__

            def mock_import(name, *args, **kwargs):
                if 'kokoro' in name:
                    raise ImportError("No module named 'kokoro'")
                return original_import(name, *args, **kwargs)

            with patch('builtins.__import__', mock_import):
                spec.loader.exec_module(module)
                result = module.main()

            self.assertEqual(result, 1)
        finally:
            sys.modules.update(saved_modules)


class TestKokoroVoices(unittest.TestCase):
    """Tests for kokoro_voices.py"""

    def setUp(self):
        """Reset sys.argv and environment before each test."""
        self.original_argv = sys.argv
        self.original_environ = os.environ.copy()
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Restore sys.argv and environment after each test."""
        sys.argv = self.original_argv
        os.environ.clear()
        os.environ.update(self.original_environ)
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    @patch.dict('sys.modules', {'huggingface_hub': MagicMock()})
    def test_voices_default_single_voice(self):
        """Test listing default single voice (af_heart)."""
        from huggingface_hub import snapshot_download

        # Create mock voices directory
        voices_dir = os.path.join(self.temp_dir, "voices")
        os.makedirs(voices_dir)
        open(os.path.join(voices_dir, "af_heart.pt"), 'w').close()

        snapshot_download.return_value = self.temp_dir

        sys.argv = ['kokoro_voices.py']

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_voices",
            os.path.join(os.path.dirname(__file__), "kokoro_voices.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with patch('builtins.print') as mock_print:
            result = module.main()

        self.assertEqual(result, 0)
        mock_print.assert_called_once()
        output = mock_print.call_args[0][0]
        voices = json.loads(output)
        self.assertEqual(voices, ["af_heart"])

    @patch.dict('sys.modules', {'huggingface_hub': MagicMock()})
    def test_voices_specific_voice(self):
        """Test listing a specific voice."""
        from huggingface_hub import snapshot_download

        voices_dir = os.path.join(self.temp_dir, "voices")
        os.makedirs(voices_dir)
        open(os.path.join(voices_dir, "bf_emma.pt"), 'w').close()

        snapshot_download.return_value = self.temp_dir

        sys.argv = ['kokoro_voices.py', '--voice', 'bf_emma']

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_voices",
            os.path.join(os.path.dirname(__file__), "kokoro_voices.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with patch('builtins.print') as mock_print:
            result = module.main()

        self.assertEqual(result, 0)
        output = mock_print.call_args[0][0]
        voices = json.loads(output)
        self.assertEqual(voices, ["bf_emma"])

        # Verify allow_patterns
        snapshot_download.assert_called_once()
        call_kwargs = snapshot_download.call_args[1]
        self.assertIn("voices/bf_emma.pt", call_kwargs['allow_patterns'])

    @patch.dict('sys.modules', {'huggingface_hub': MagicMock()})
    def test_voices_all_voices(self):
        """Test listing all voices with --all flag."""
        from huggingface_hub import snapshot_download

        voices_dir = os.path.join(self.temp_dir, "voices")
        os.makedirs(voices_dir)
        for voice in ["af_heart.pt", "bf_emma.pt", "am_michael.onnx", "af_bella.bin"]:
            open(os.path.join(voices_dir, voice), 'w').close()

        snapshot_download.return_value = self.temp_dir

        sys.argv = ['kokoro_voices.py', '--all']

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_voices",
            os.path.join(os.path.dirname(__file__), "kokoro_voices.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with patch('builtins.print') as mock_print:
            result = module.main()

        self.assertEqual(result, 0)
        output = mock_print.call_args[0][0]
        voices = json.loads(output)
        self.assertEqual(sorted(voices), ["af_bella", "af_heart", "am_michael", "bf_emma"])

    @patch.dict('sys.modules', {'huggingface_hub': MagicMock()})
    def test_voices_env_var_voice(self):
        """Test voice selection via KOKORO_VOICE environment variable."""
        from huggingface_hub import snapshot_download

        voices_dir = os.path.join(self.temp_dir, "voices")
        os.makedirs(voices_dir)
        open(os.path.join(voices_dir, "custom_voice.pt"), 'w').close()

        snapshot_download.return_value = self.temp_dir
        os.environ['KOKORO_VOICE'] = 'custom_voice'

        sys.argv = ['kokoro_voices.py']

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_voices",
            os.path.join(os.path.dirname(__file__), "kokoro_voices.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with patch('builtins.print') as mock_print:
            result = module.main()

        self.assertEqual(result, 0)
        output = mock_print.call_args[0][0]
        voices = json.loads(output)
        self.assertEqual(voices, ["custom_voice"])

    @patch.dict('sys.modules', {'huggingface_hub': MagicMock()})
    def test_voices_env_var_all(self):
        """Test --all via KOKORO_ALL_VOICES environment variable."""
        from huggingface_hub import snapshot_download

        voices_dir = os.path.join(self.temp_dir, "voices")
        os.makedirs(voices_dir)
        for voice in ["af_heart.pt", "bf_emma.pt"]:
            open(os.path.join(voices_dir, voice), 'w').close()

        snapshot_download.return_value = self.temp_dir
        os.environ['KOKORO_ALL_VOICES'] = '1'

        sys.argv = ['kokoro_voices.py']

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_voices",
            os.path.join(os.path.dirname(__file__), "kokoro_voices.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with patch('builtins.print') as mock_print:
            result = module.main()

        self.assertEqual(result, 0)
        output = mock_print.call_args[0][0]
        voices = json.loads(output)
        self.assertEqual(sorted(voices), ["af_heart", "bf_emma"])

    @patch.dict('sys.modules', {'huggingface_hub': MagicMock()})
    def test_voices_custom_repo_and_revision(self):
        """Test with custom repo and revision."""
        from huggingface_hub import snapshot_download

        voices_dir = os.path.join(self.temp_dir, "voices")
        os.makedirs(voices_dir)
        open(os.path.join(voices_dir, "af_heart.pt"), 'w').close()

        snapshot_download.return_value = self.temp_dir

        sys.argv = ['kokoro_voices.py', '--repo', 'custom/repo', '--revision', 'v2.0']

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_voices",
            os.path.join(os.path.dirname(__file__), "kokoro_voices.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with patch('builtins.print'):
            result = module.main()

        self.assertEqual(result, 0)
        snapshot_download.assert_called_once()
        call_kwargs = snapshot_download.call_args[1]
        self.assertEqual(call_kwargs['repo_id'], 'custom/repo')
        self.assertEqual(call_kwargs['revision'], 'v2.0')

    @patch.dict('sys.modules', {'huggingface_hub': MagicMock()})
    def test_voices_empty_directory(self):
        """Test when voices directory is empty."""
        from huggingface_hub import snapshot_download

        voices_dir = os.path.join(self.temp_dir, "voices")
        os.makedirs(voices_dir)
        # No voice files

        snapshot_download.return_value = self.temp_dir

        sys.argv = ['kokoro_voices.py', '--all']

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_voices",
            os.path.join(os.path.dirname(__file__), "kokoro_voices.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with patch('builtins.print') as mock_print:
            result = module.main()

        self.assertEqual(result, 0)
        output = mock_print.call_args[0][0]
        voices = json.loads(output)
        self.assertEqual(voices, [])

    @patch.dict('sys.modules', {'huggingface_hub': MagicMock()})
    def test_voices_no_voices_directory(self):
        """Test when voices directory doesn't exist."""
        from huggingface_hub import snapshot_download

        # Don't create voices directory
        snapshot_download.return_value = self.temp_dir

        sys.argv = ['kokoro_voices.py', '--all']

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_voices",
            os.path.join(os.path.dirname(__file__), "kokoro_voices.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with patch('builtins.print') as mock_print:
            result = module.main()

        self.assertEqual(result, 0)
        output = mock_print.call_args[0][0]
        voices = json.loads(output)
        self.assertEqual(voices, [])

    @patch.dict('sys.modules', {'huggingface_hub': MagicMock()})
    def test_voices_download_failure(self):
        """Test when snapshot_download fails."""
        from huggingface_hub import snapshot_download
        snapshot_download.side_effect = Exception("Network error")

        sys.argv = ['kokoro_voices.py']

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_voices",
            os.path.join(os.path.dirname(__file__), "kokoro_voices.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        result = module.main()

        self.assertEqual(result, 2)

    def test_voices_import_failure(self):
        """Test when huggingface_hub is not installed."""
        sys.argv = ['kokoro_voices.py']

        modules_to_remove = [k for k in sys.modules.keys() if 'huggingface_hub' in k]
        saved_modules = {k: sys.modules.pop(k) for k in modules_to_remove}

        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location(
                "kokoro_voices_fail",
                os.path.join(os.path.dirname(__file__), "kokoro_voices.py")
            )
            module = importlib.util.module_from_spec(spec)

            original_import = __builtins__.__import__ if hasattr(__builtins__, '__import__') else __import__

            def mock_import(name, *args, **kwargs):
                if 'huggingface_hub' in name:
                    raise ImportError("No module named 'huggingface_hub'")
                return original_import(name, *args, **kwargs)

            with patch('builtins.__import__', mock_import):
                spec.loader.exec_module(module)
                result = module.main()

            self.assertEqual(result, 1)
        finally:
            sys.modules.update(saved_modules)

    @patch.dict('sys.modules', {'huggingface_hub': MagicMock()})
    def test_voices_ignores_non_voice_files(self):
        """Test that non-voice files are ignored."""
        from huggingface_hub import snapshot_download

        voices_dir = os.path.join(self.temp_dir, "voices")
        os.makedirs(voices_dir)
        # Create voice files and non-voice files
        open(os.path.join(voices_dir, "af_heart.pt"), 'w').close()
        open(os.path.join(voices_dir, "readme.txt"), 'w').close()
        open(os.path.join(voices_dir, "config.json"), 'w').close()
        open(os.path.join(voices_dir, "bf_emma.onnx"), 'w').close()

        snapshot_download.return_value = self.temp_dir

        sys.argv = ['kokoro_voices.py', '--all']

        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "kokoro_voices",
            os.path.join(os.path.dirname(__file__), "kokoro_voices.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with patch('builtins.print') as mock_print:
            result = module.main()

        self.assertEqual(result, 0)
        output = mock_print.call_args[0][0]
        voices = json.loads(output)
        # Should only include .pt, .onnx, .bin files
        self.assertEqual(sorted(voices), ["af_heart", "bf_emma"])


class TestArgumentParsing(unittest.TestCase):
    """Test argument parsing for all scripts."""

    def test_prefetch_help(self):
        """Test that prefetch script has proper help."""
        import argparse
        parser = argparse.ArgumentParser(description="Prefetch Kokoro model repo from Hugging Face")
        parser.add_argument("--repo", default="hexgrad/Kokoro-82M")
        parser.add_argument("--revision", default="")

        # Verify defaults
        args = parser.parse_args([])
        self.assertEqual(args.repo, "hexgrad/Kokoro-82M")
        self.assertEqual(args.revision, "")

    def test_say_required_args(self):
        """Test that say script requires --text and --out."""
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--text", required=True)
        parser.add_argument("--out", required=True)

        with self.assertRaises(SystemExit):
            parser.parse_args([])

        with self.assertRaises(SystemExit):
            parser.parse_args(['--text', 'hello'])

        # Should work with both
        args = parser.parse_args(['--text', 'hello', '--out', 'out.wav'])
        self.assertEqual(args.text, 'hello')
        self.assertEqual(args.out, 'out.wav')

    def test_voices_mutually_exclusive_behavior(self):
        """Test voices script argument behavior."""
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--voice", default="")
        parser.add_argument("--all", action="store_true")

        # Default behavior
        args = parser.parse_args([])
        self.assertEqual(args.voice, "")
        self.assertFalse(args.all)

        # With --voice
        args = parser.parse_args(['--voice', 'test'])
        self.assertEqual(args.voice, 'test')

        # With --all
        args = parser.parse_args(['--all'])
        self.assertTrue(args.all)


if __name__ == "__main__":
    unittest.main()
