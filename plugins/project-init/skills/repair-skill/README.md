# repair-skill

기존 SKILL.md를 평가하고 승인된 항목만 직접 수정하는 `project-init` 스킬.

## 무엇을

`../../shared/rubric/criteria.md` 30항목(규칙 17 + 모델 13) 기준으로 평가해
등급과 BLOCKER·MAJOR 지적을 산출한다. BLOCKER·MAJOR가 있으면 항목별 수정안과
diff를 제시해 사용자 승인을 받고, 승인된 항목만 직접 반영한 뒤 재평가로 해소
여부를 확인한다.

## 언제

사용자가 기존 스킬의 품질 점검·진단·수정·보수·고치기·리페어를 요청하거나
BLOCKER·MAJOR 해소가 필요할 때 활성화된다.
정확한 트리거 표현은 `SKILL.md`의 `description`이 단일 출처다.

## 어떻게 호출

```
Skill(skill="repair-skill", args="<SKILL.md 경로 | all>")
```

`all`이면 저장소 전체 SKILL.md를 대상으로 스킬마다 독립적으로 평가·승인을
진행한다.

## 진입점·포인터

- 동작 명세(절차·규칙)의 단일 출처: [`SKILL.md`](./SKILL.md)
- 루브릭 30항목 기준(단일 출처): [`../../shared/rubric/criteria.md`](../../shared/rubric/criteria.md)
- 규칙 17항목 검사기: [`../../shared/rubric/rule_checker.py`](../../shared/rubric/rule_checker.py)

> 이 문서는 폴더 진입점용 요약이다. 진행 순서·규칙 본문은 `SKILL.md`에만 두며 여기서 복제하지 않는다.
