"""
Tests for Azure Functions API endpoints and utilities.
"""
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestTemplateIdSanitization:
    """Tests for template ID sanitization and validation."""

    def test_sanitize_lowercase(self):
        """Test that uppercase is converted to lowercase."""
        from function_app import sanitize_template_id
        assert sanitize_template_id("EXECUTIVE") == "executive"
        assert sanitize_template_id("MyTemplate") == "mytemplate"

    def test_sanitize_spaces_to_hyphens(self):
        """Test that spaces are converted to hyphens."""
        from function_app import sanitize_template_id
        assert sanitize_template_id("my template") == "my-template"
        assert sanitize_template_id("Q4 Budget Review") == "q4-budget-review"

    def test_sanitize_special_chars_removed(self):
        """Test that special characters are removed."""
        from function_app import sanitize_template_id
        assert sanitize_template_id("template(v2)") == "templatev2"
        assert sanitize_template_id("my@template!") == "mytemplate"
        assert sanitize_template_id("test#123") == "test123"

    def test_sanitize_pptx_extension_removed(self):
        """Test that .pptx extension is removed."""
        from function_app import sanitize_template_id
        assert sanitize_template_id("executive.pptx") == "executive"
        assert sanitize_template_id("My Template.pptx") == "my-template"

    def test_sanitize_collapse_hyphens(self):
        """Test that multiple hyphens are collapsed."""
        from function_app import sanitize_template_id
        assert sanitize_template_id("my--template") == "my-template"
        assert sanitize_template_id("a - b - c") == "a-b-c"

    def test_sanitize_strip_leading_trailing(self):
        """Test that leading/trailing hyphens are stripped."""
        from function_app import sanitize_template_id
        assert sanitize_template_id("-template-") == "template"
        assert sanitize_template_id("_template_") == "template"

    def test_validate_valid_ids(self):
        """Test validation of valid template IDs."""
        from function_app import validate_template_id
        assert validate_template_id("executive")[0] is True
        assert validate_template_id("q4-budget-review")[0] is True
        assert validate_template_id("template123")[0] is True
        assert validate_template_id("a")[0] is True
        assert validate_template_id("my_template")[0] is True

    def test_validate_invalid_ids(self):
        """Test validation of invalid template IDs."""
        from function_app import validate_template_id
        assert validate_template_id("")[0] is False
        assert validate_template_id("-starts-with-hyphen")[0] is False
        assert validate_template_id("ends-with-hyphen-")[0] is False
        assert validate_template_id("has spaces")[0] is False

    def test_validate_max_length(self):
        """Test validation of max length."""
        from function_app import validate_template_id, MAX_TEMPLATE_ID_LENGTH
        long_id = "a" * (MAX_TEMPLATE_ID_LENGTH + 1)
        assert validate_template_id(long_id)[0] is False

        valid_id = "a" * MAX_TEMPLATE_ID_LENGTH
        assert validate_template_id(valid_id)[0] is True


class TestServicesImport:
    """Test that services can be imported without errors."""

    def test_import_services(self):
        """Test importing the services module."""
        from src import services
        assert hasattr(services, 'ServiceBusService')
        assert hasattr(services, 'CosmosService')
        assert hasattr(services, 'BlobStorageService')
        assert hasattr(services, 'TemplateIntrospectionService')

    def test_import_models(self):
        """Test importing the models module."""
        from src import models
        assert hasattr(models, 'GenerationRequest')
        assert hasattr(models, 'JobStatus')


class TestTemplateIntrospection:
    """Tests for template introspection service."""

    def test_placeholder_type_map(self):
        """Test that placeholder type mapping is defined."""
        from src.services import TemplateIntrospectionService
        service = TemplateIntrospectionService()
        assert "TITLE" in service.PLACEHOLDER_TYPE_MAP
        assert "OBJECT" in service.PLACEHOLDER_TYPE_MAP
        assert service.PLACEHOLDER_TYPE_MAP["TITLE"] == "title"
        assert service.PLACEHOLDER_TYPE_MAP["OBJECT"] == "mixed"

    def test_accepts_map(self):
        """Test that accepts mapping is defined."""
        from src.services import TemplateIntrospectionService
        service = TemplateIntrospectionService()
        assert "mixed" in service.ACCEPTS_MAP
        assert "chart" in service.ACCEPTS_MAP["mixed"]
        assert "table" in service.ACCEPTS_MAP["mixed"]

    def test_generate_name(self):
        """Test template name generation from ID."""
        from src.services import TemplateIntrospectionService
        service = TemplateIntrospectionService()
        assert service._generate_name("executive-summary") == "Executive Summary"
        assert service._generate_name("q4_budget") == "Q4 Budget"


def run_tests():
    """Run all tests and print results."""
    import traceback

    test_classes = [
        TestTemplateIdSanitization,
        TestServicesImport,
        TestTemplateIntrospection,
    ]

    passed = 0
    failed = 0
    errors = []

    for test_class in test_classes:
        instance = test_class()
        for method_name in dir(instance):
            if method_name.startswith('test_'):
                try:
                    getattr(instance, method_name)()
                    passed += 1
                    print(f"  ✓ {test_class.__name__}.{method_name}")
                except AssertionError as e:
                    failed += 1
                    errors.append((test_class.__name__, method_name, str(e)))
                    print(f"  ✗ {test_class.__name__}.{method_name}: {e}")
                except Exception as e:
                    failed += 1
                    errors.append((test_class.__name__, method_name, traceback.format_exc()))
                    print(f"  ✗ {test_class.__name__}.{method_name}: {e}")

    print(f"\n{'='*50}")
    print(f"Results: {passed} passed, {failed} failed")

    if errors:
        print(f"\nFailures:")
        for cls, method, error in errors:
            print(f"  - {cls}.{method}")

    return failed == 0


if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
