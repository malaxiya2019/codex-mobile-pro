import 'package:flutter_test/flutter_test.dart';
import 'package:codex_mobile_pro/features/project/models/project_template.dart';
import 'package:codex_mobile_pro/features/project/services/project_generator.dart';
import 'package:codex_mobile_pro/features/project/services/templates/flutter_template_generator.dart';
import 'package:codex_mobile_pro/features/project/services/templates/rust_template_generator.dart';
import 'package:codex_mobile_pro/features/project/services/templates/python_template_generator.dart';

void main() {
  group('ProjectGeneratorService', () {
    late ProjectGeneratorService service;

    setUp(() {
      service = ProjectGeneratorService();
    });

    test('初始无模板', () {
      expect(service.availableTemplates, isEmpty);
    });

    test('注册 Flutter 模板', () {
      service.register(FlutterTemplateGenerator());
      expect(service.availableTemplates.length, 1);
      expect(
        service.availableTemplates.first.type,
        ProjectTemplateType.flutter,
      );
    });

    test('注册所有模板', () {
      service.register(FlutterTemplateGenerator());
      service.register(RustTemplateGenerator());
      service.register(PythonTemplateGenerator());

      expect(service.availableTemplates.length, 3);
      expect(service.getTemplate(ProjectTemplateType.flutter), isNotNull);
      expect(service.getTemplate(ProjectTemplateType.rust), isNotNull);
      expect(service.getTemplate(ProjectTemplateType.python), isNotNull);
    });

    test('重复注册覆盖', () {
      service.register(FlutterTemplateGenerator());
      service.register(FlutterTemplateGenerator());
      expect(service.availableTemplates.length, 1);
    });

    test('获取不存在的模板返回 null', () {
      expect(service.getTemplate(ProjectTemplateType.flutter), isNull);
    });

    test('不支持的模板类型返回错误结果', () async {
      final result = await service.createProject(
        ProjectCreateConfig(
          name: 'Test',
          path: '/tmp',
          type: ProjectTemplateType.flutter,
        ),
      );
      expect(result.success, false);
      expect(result.errorMessage, contains('不支持的模板类型'));
    });
  });

  group('FlutterTemplateGenerator', () {
    late FlutterTemplateGenerator generator;

    setUp(() {
      generator = FlutterTemplateGenerator();
    });

    test('模板类型正确', () {
      expect(generator.type, ProjectTemplateType.flutter);
    });

    test('模板信息正确', () {
      final tpl = generator.template;
      expect(tpl.id, 'flutter-default');
      expect(tpl.type, ProjectTemplateType.flutter);
      expect(tpl.requiredTools, contains('flutter'));
      expect(tpl.generatedFiles, contains('lib/main.dart'));
    });

    test('环境检测返回列表', () async {
      final missing = await generator.checkRequirements();
      expect(missing, isA<List<String>>());
    });
  });

  group('RustTemplateGenerator', () {
    late RustTemplateGenerator generator;

    setUp(() {
      generator = RustTemplateGenerator();
    });

    test('模板类型正确', () {
      expect(generator.type, ProjectTemplateType.rust);
    });

    test('模板信息正确', () {
      final tpl = generator.template;
      expect(tpl.id, 'rust-default');
      expect(tpl.type, ProjectTemplateType.rust);
      expect(tpl.requiredTools, contains('cargo'));
      expect(tpl.generatedFiles, contains('Cargo.toml'));
    });
  });

  group('PythonTemplateGenerator', () {
    late PythonTemplateGenerator generator;

    setUp(() {
      generator = PythonTemplateGenerator();
    });

    test('模板类型正确', () {
      expect(generator.type, ProjectTemplateType.python);
    });

    test('模板信息正确', () {
      final tpl = generator.template;
      expect(tpl.id, 'python-default');
      expect(tpl.type, ProjectTemplateType.python);
      expect(tpl.requiredTools, contains('python3'));
      expect(tpl.generatedFiles, contains('main.py'));
    });
  });
}
