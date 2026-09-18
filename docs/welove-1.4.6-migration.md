# welove upstream 재검사 연동

기준: 업스트림 `4f5edc201` (PR #246, 1.4.7 이후) 위에 RN 외부 UI 연결을 리베이스했다.
iOS 15 이상이며 amplify-swift 의존성은 upstream과 동일한 `from: "2.60.2"`다.
빌드 간 비교 시에는 실제 해석된 `Package.resolved` 버전도 같아야 한다.

## Native 모드

`FaceLivenessViewCustomization()` 기본값은 upstream 준비·촬영·검증 UI를 사용한다.
`externalFreshnessController`가 없으면 색상 재생과 재시도 처리도 upstream 경로를 따른다.
카메라 비율은 upstream `LivenessPreviewGeometry`의 중앙 3:4이며, 로컬 타원 확대,
매칭 허용치 변경, 전체 화면 crop, 점선/pulse 효과는 제거했다.

RN 모드에서는 `externalFreshnessController`와 shooting/verification overlay만 전달한다.
준비 화면 교체도 외부 컨트롤러가 있는 RN 모드에만 적용된다.
이하의 준비 응답·취소 계약은 RN 모드에만 적용된다.

공통 `LivenessStateMachine`은 upstream 원본이다. `.faceMatched`에서 얼굴이 사라졌을 때
매칭 대기로 돌리는 확장은 RN 분기에서만 처리하며 Native의 상태 전이를 바꾸지 않는다.
`FaceStateMatching`, `OvalView`, `LivenessPreviewGeometry`, `Freshness`, `FreshnessView`,
카메라·영상 전송·AWS 이벤트 직렬화 코드는 upstream을 그대로 사용한다.
RN은 별도 색상 타이머와 외부 UI를 사용하므로 Native와 confidence가 같다고 보장하지 않는다.

## 얼굴 이탈 후 재시도

색상 검사 중 얼굴이 사라지거나 여러 얼굴이 감지되면 SDK는 색상 재생을
취소하고 얼굴 맞추기로 돌아간다. 얼굴이 다시 맞으면 같은 세션에서 색상
시퀀스를 처음부터 새로 전달한다. 얼굴이 돌아오지 않으면 기존 얼굴 맞추기
타임아웃으로 종료한다.

얼굴을 맞춘 직후의 1초 대기 중에도 얼굴 이탈을 처리한다. 이때나 세션 종료
시에는 예약된 색상 시작 작업도 취소해, 뒤늦게 검사가 다시 시작되지 않게 한다.

RN 브리지는 다음 계약을 연결해야 한다.

1. `onFreshnessSequencePrepared`의 `sequenceID.uuidString`을 프레임과 함께 RN에 전달한다.
2. RN은 새 시퀀스를 받을 때 이전 애니메이션과 예약 작업을 모두 취소한다.
3. 준비 완료 응답에 같은 ID를 담고 Swift에서
   `acknowledgeFreshnessReady(sequenceID:)`를 호출한다.
4. `onCancelled`로 전달된 시퀀스 ID가 현재 표시 중인 ID라면 RN 색상 레이어와
   타이머를 즉시 정리한다. 취소를 성공 완료로 처리하지 않는다.
5. 다음 준비 이벤트를 받으면 새 ID로 다시 시작한다. 이전 회차의 늦은 준비
   응답은 SDK가 무시한다.

인자 없는 `acknowledgeFreshnessReady()`는 기존 호출부의 소스 호환성을 위해
남아 있지만 회차를 구분할 수 없다. 재시도를 사용하는 RN 브리지는 반드시
ID를 전달하는 API로 전환해야 한다.

RN 화면 코드는 이 저장소에 포함되어 있지 않다. SDK 업데이트만으로 RN에서
독립적으로 예약한 애니메이션이 취소되지는 않는다.

## 에러 처리

전화 수신, 앱 백그라운드 전환 등은 이제 `sessionInterrupted`(code 19)로
전달된다. 사용자가 직접 취소한 `userCancelled`와 구분해 새 세션으로 재시도할
수 있는 화면을 표시한다. 얼굴 이탈에 따른 동일 세션 내 재매칭과는 다르다.

## 실제 기기 확인

- 색상 재생 중 얼굴 이탈 및 여러 얼굴 감지 → 색상 중단 → 얼굴 복귀 → 새 시퀀스 재생.
- RN 준비 응답 대기 중 얼굴 이탈 → 이전 응답 무시 → 새 회차 응답으로만 시작.
- 반복 이탈, 얼굴 맞추기 타임아웃, 사용자 취소, 앱 백그라운드 전환.
- 정상 종료·취소·오류 이후 화면 밝기 복원.
- Native 모드에서 AWS 기본 준비·촬영·검증 화면이 보이고 RN 콜백이 발생하지 않는지 확인.

## RN 추가 얼굴 크기 조건

외부 컨트롤러의 `minimumFaceSizeRatio`(0 이상 유한값, 기본 0)는 AWS oval 대비 판정 박스의
최소 가로·세로 비율이다. AWS가 `.match`를 반환한 경우에만 추가 검사하며,
어느 한쪽이라도 부족하면 `.tooFar`로 안내하고 기존 얼굴 맞추기 타임아웃을 따른다.
Native는 외부 컨트롤러가 없어 이 조건을 실행하지 않는다.
예제 앱은 iOS RN에 0을 전달해 추가 조건을 해제하고 AWS 기본 판정을 사용한다.

비율의 상한을 1로 제한하지 않는다. AWS의 too-close 조건은 유지하므로 110% 조건과
동시에 만족할 수 없는 기기/세션에서는 시작이 지연되거나 기존 타임아웃으로 종료될 수 있다.

## RN oval과 녹화 표시

AWS 설정과 카메라 레이아웃이 준비되면 실제 oval을 얼굴 준비 판정 전에 RN으로 전달한다.
표시 전용 전달이므로 판정용 oval·녹화 시작·AWS 이벤트 시점은 바꾸지 않는다.
RN은 전달받은 oval의 세로만 10% 줄여 표시한다. 카메라와 실제 판정 영역은 유지한다.
촬영 overlay는 UI 이벤트의 `isRecording`으로 준비 단계에서는 REC를 숨기고 얼굴 맞추기부터 표시한다.
얼굴 박스 측정용 API·이벤트·디버그 오버레이는 제거했다.
