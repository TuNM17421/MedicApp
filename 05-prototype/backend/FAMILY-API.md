# API liên kết hai máy

Máy người chăm sóc (chủ hồ sơ, `owner`) liên kết một hồ sơ gia đình, ví dụ Mẹ Lan, với điện thoại của chính người đó (`member`). Sau khi liên kết:

- Lịch hẹn đi cả hai chiều.
- Đơn thuốc của người được liên kết đi từ máy chủ hồ sơ sang máy người đó, để chuông báo uống thuốc kêu ở máy của người uống.
- Máy người được liên kết gửi lịch liều của mình. Máy chủ hồ sơ chỉ nhận tin khi người đó quên hoặc bỏ liều.
- Thuốc của chủ hồ sơ không bao giờ rời máy chủ hồ sơ.

Quy ước chung (JSON, lỗi, giờ `+07:00`) giống [API phòng khám](CLINIC-API.md). Nhật ký server chỉ ghi tên sự kiện và số lượng, không ghi tên người, tên thuốc, mã hay token.

## Mã liên kết

| Giao diện | Thân | Trả về |
| --- | --- | --- |
| `POST /v1/family/links` | `{ ownerName, profile: { name, relationship, birthYear, gender? } }` | `201 { link, token, invite }`. `token` là của máy chủ hồ sơ. |
| `POST /v1/family/links/:id/invite` | (owner) | `200 { invite }`: mã mới, mã cũ hết hiệu lực. |
| `POST /v1/family/peek` | `{ code }` | `200 { ownerName, profile }` để máy người được liên kết hỏi đồng ý trước khi nhận. |
| `POST /v1/family/claim` | `{ code, memberName, shareMissed? }` | `200 { link, token }`. `token` là của máy người được liên kết. |
| `GET /v1/family/links/:id` | (một trong hai bên) | `200 link` |
| `DELETE /v1/family/links/:id` | (một trong hai bên) | `200 link` với `status: "ended"`. Bên kia nhận `link.ended`. |
| `PUT /v1/family/links/:id/settings` | `{ shareMissed }` (member) | `200 link`. Bên kia nhận `link.settings`. |

Quy tắc của mã:

- `invite = { code: "ABCD-EF23", expiresAt }`. Mã có 8 ký tự, không dùng 0/O, 1/I/L. Mã hết hạn sau 15 phút và chỉ dùng được một lần.
- QR chứa `medicapp://lien-ket?ma=ABCD-EF23`.
- Server nhận mã viết thường, có hoặc không có dấu gạch.
- Mã sai hoặc hết hạn trả `404 bad_code`.
- `peek` và `claim` giới hạn 10 lần mỗi phút cho mỗi địa chỉ, quá thì trả `429 rate_limited`.

Token và hiệu lực:

- Hai bên gửi token bằng `authorization: Bearer <token>`.
- Server chỉ giữ SHA-256 của token và của mã.
- Token sai trả `401 unauthenticated`.
- Gửi vào một liên kết đã hủy trả `409 link_ended`.
- `link = { id, role, status: "pending" | "linked" | "ended", ownerName, memberName, profile, shareMissed }`.

## Hộp tin

| Giao diện | Thân | Trả về |
| --- | --- | --- |
| `POST /v1/family/links/:id/events` | `{ events: [{ kind, id, body? }] }` (tối đa 50) | `200 { accepted }` |
| `GET /v1/family/links/:id/events?after=<seq>` | | `200 { status, cursor, more, events: [{ seq, kind, id, body, at }] }` |
| `PUT /v1/family/links/:id/doses` | `{ doses: [{ key, at, label, meds }], marks: [{ key, mark, reason?, at }] }` (member) | `200 { doses, alerts }` |

Mỗi bên chỉ đọc tin bên kia gửi:

- Máy chủ hồ sơ gửi được `appointment.upsert`, `appointment.cancel` và `result.upsert`.
- Máy người được liên kết chỉ gửi được `appointment.*`. Gửi loại khác trả `403 forbidden`.
- Server tự thêm `link.claimed`, `link.settings`, `link.ended` và các tin `dose.*`.
- Mỗi lần đọc trả tối đa 100 tin. `more: true` nghĩa là còn tin, đọc tiếp với `after=cursor`.

Lịch liều và tin lỡ liều:

- `doses` là các liều sắp tới, mỗi buổi một dòng, chỉ có tên thuốc. `marks` là các liều đã ghi "Đã uống" hoặc "Bỏ liều".
- Một liều quá 60 phút mà chưa ghi sẽ thành `dose.missed`. Server tính lúc máy chủ hồ sơ đọc tin, nên không phụ thuộc máy người được liên kết đang mở hay tắt.
- Bỏ liều thành `dose.skipped`, có `reason` là `forgot`, `outOfStock`, `unwell` hoặc `other`.
- Đã báo lỡ hoặc bỏ liều mà sau đó người dùng ghi đã uống thì server gửi `dose.taken`.
- Mỗi liều chỉ được báo một lần.
- Khi `shareMissed` tắt, server không tạo tin `dose.*`.
- Lịch liều được giữ 7 ngày.

## Chạy và kiểm thử

Liên kết dùng chung cơ sở dữ liệu với phần phòng khám (bảng `family_link`, `family_invite`, `family_event`, `family_dose`). Lệnh `node --test test/family.test.js` chạy 7 test.
