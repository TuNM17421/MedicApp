/// Five conditions whose visits need preparation, written from public patient
/// guidance (sources listed per entry, read 2026-10-15). Prototype content:
/// it needs review by a clinician before real use, and the facility's own
/// instructions always win.
class PrepSource {
  const PrepSource(this.title, this.url);
  final String title;
  final String url;
}

class PrepCondition {
  const PrepCondition({
    required this.id,
    required this.name,
    required this.departmentIds,
    required this.visitLabel,
    required this.steps,
    required this.sources,
    this.fastingHours,
    this.liquidStopHours,
    this.noAlcoholHours,
    this.noSmokeCaffeineMinutes,
    this.sedation = false,
  });
  final String id;

  /// As said to the patient, e.g. "đái tháo đường".
  final String name;

  /// Departments where a visit for this condition usually includes [visitLabel].
  final List<String> departmentIds;
  final String visitLabel;

  /// No food (plain water allowed) for at least this long before the visit.
  final int? fastingHours;

  /// No drinks at all, plain water included, for this long before the visit.
  final int? liquidStopHours;
  final int? noAlcoholHours;
  final int? noSmokeCaffeineMinutes;

  /// The procedure may be done under sedation, so someone should take the
  /// patient home.
  final bool sedation;

  /// Other preparation in plain words, shown after the timed items.
  final List<String> steps;
  final List<PrepSource> sources;
}

abstract final class VisitPrepCatalog {
  static const conditions = [
    PrepCondition(
      id: 'diabetes',
      name: 'đái tháo đường',
      departmentIds: ['endocrine'],
      visitLabel: 'xét nghiệm đường huyết lúc đói',
      fastingHours: 8,
      steps: [
        'Không uống cà phê, nước ngọt, sữa, không nhai kẹo cao su hay hút thuốc trong lúc nhịn ăn.',
        'Mang theo thuốc đang dùng hoặc đơn thuốc, và sổ theo dõi đường huyết nếu có.',
      ],
      sources: [
        PrepSource(
          'MedlinePlus: Blood Glucose Test',
          'https://medlineplus.gov/lab-tests/blood-glucose-test/',
        ),
        PrepSource(
          'MedlinePlus: Fasting for a Blood Test',
          'https://medlineplus.gov/lab-tests/fasting-for-a-blood-test/',
        ),
      ],
    ),
    PrepCondition(
      id: 'dyslipidemia',
      name: 'rối loạn mỡ máu',
      departmentIds: ['heart', 'endocrine'],
      visitLabel: 'xét nghiệm mỡ máu',
      fastingHours: 9,
      noAlcoholHours: 24,
      steps: [
        'Có thể uống nước lọc trong lúc nhịn ăn. Không uống đồ có gas.',
        'Cơ sở có thể dặn nhịn 9 đến 12 tiếng; nếu được dặn khác, làm theo cơ sở.',
      ],
      sources: [
        PrepSource(
          'MedlinePlus: Cholesterol Levels',
          'https://medlineplus.gov/lab-tests/cholesterol-levels/',
        ),
        PrepSource(
          'MEDLATEC: Xét nghiệm mỡ máu có cần nhịn ăn không',
          'https://medlatec.vn/tin-tuc/xet-nghiem-mo-mau-co-can-nhin-an-khong-giai-dap-chi-tiet',
        ),
      ],
    ),
    PrepCondition(
      id: 'hypertension',
      name: 'tăng huyết áp',
      departmentIds: ['heart'],
      visitLabel: 'đo huyết áp',
      noSmokeCaffeineMinutes: 30,
      steps: [
        'Không tập thể dục trong 30 phút trước khi đo.',
        'Đi vệ sinh trước khi đo, rồi ngồi nghỉ yên lặng ít nhất 5 phút.',
        'Mang theo thuốc huyết áp đang dùng và sổ ghi huyết áp ở nhà nếu có.',
      ],
      sources: [
        PrepSource(
          'American Heart Association: Monitoring Your Blood Pressure at Home',
          'https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings/monitoring-your-blood-pressure-at-home',
        ),
      ],
    ),
    PrepCondition(
      id: 'gout',
      name: 'gút',
      departmentIds: ['bones'],
      visitLabel: 'xét nghiệm acid uric máu',
      fastingHours: 4,
      noAlcoholHours: 24,
      steps: [
        'Có thể uống nước lọc trong lúc nhịn ăn.',
        'Báo bác sĩ nếu đang dùng aspirin, ibuprofen hoặc vitamin C. Không tự ý ngừng thuốc.',
      ],
      sources: [
        PrepSource(
          'Bệnh viện Tâm Anh: Xét nghiệm acid uric máu',
          'https://tamanhhospital.vn/xet-nghiem-acid-uric-mau/',
        ),
        PrepSource(
          'UCSF Health: Uric acid - blood',
          'https://www.ucsfhealth.org/medical-tests/003476',
        ),
      ],
    ),
    PrepCondition(
      id: 'gastritis',
      name: 'viêm dạ dày',
      departmentIds: ['general'],
      visitLabel: 'nội soi dạ dày',
      fastingHours: 6,
      liquidStopHours: 2,
      sedation: true,
      steps: [
        'Sữa và đồ uống có màu thì ngừng trước ít nhất 4 tiếng.',
        'Thuốc uống hằng ngày nên uống trước giờ hẹn ít nhất 3 tiếng. Không uống thuốc dạ dày dạng sữa (như Phosphalugel) vào sáng hôm nội soi.',
        'Mang theo đơn thuốc hoặc danh sách thuốc đang dùng.',
      ],
      sources: [
        PrepSource(
          'Bệnh viện Tâm Anh: Hướng dẫn người bệnh trước khi nội soi tiêu hóa',
          'https://tamanhhospital.vn/huong-dan-nguoi-benh-truoc-khi-noi-soi/',
        ),
        PrepSource(
          'HealthPartners: EGD, preparing for your procedure',
          'https://www.healthpartners.com/content/dam/brand-identity/pdfs/care/Esophagogastroduodenoscopy-EGD-preparing-for-your-procedure.pdf',
        ),
      ],
    ),
  ];

  static PrepCondition? byId(String id) =>
      conditions.where((condition) => condition.id == id).firstOrNull;

  /// Patient-facing label, capitalised.
  static String label(PrepCondition condition) =>
      '${condition.name[0].toUpperCase()}${condition.name.substring(1)}';
}
