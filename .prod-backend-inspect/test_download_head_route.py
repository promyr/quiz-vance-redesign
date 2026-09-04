import ast
import unittest
from pathlib import Path


MAIN_PATH = Path(__file__).parent / "app" / "main.py"


class DownloadHeadRouteTest(unittest.TestCase):
    def test_latest_apk_route_accepts_get_and_head(self) -> None:
        module = ast.parse(MAIN_PATH.read_text(encoding="utf-8-sig"))

        route_methods: set[str] | None = None
        for node in module.body:
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            if node.name != "app_download_android_latest":
                continue
            for decorator in node.decorator_list:
                if not isinstance(decorator, ast.Call):
                    continue
                if not isinstance(decorator.func, ast.Attribute):
                    continue
                if decorator.func.attr != "api_route":
                    continue
                methods_keyword = next(
                    (keyword for keyword in decorator.keywords if keyword.arg == "methods"),
                    None,
                )
                if methods_keyword and isinstance(methods_keyword.value, (ast.List, ast.Tuple)):
                    route_methods = {
                        element.value
                        for element in methods_keyword.value.elts
                        if isinstance(element, ast.Constant)
                        and isinstance(element.value, str)
                    }

        self.assertEqual({"GET", "HEAD"}, route_methods)


if __name__ == "__main__":
    unittest.main()
