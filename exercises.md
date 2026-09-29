# Phiếu Phản Ánh — K4 Level 3B, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Đã hoàn thành trả lời đầy đủ 10 câu hỏi bên dưới.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Đặng Quang Hưng  Mã học viên: 2A202602719

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Tình huống: Khi deploy ứng dụng lên môi trường Production trên Cloud (như Railway/Render), developer quên khai báo biến môi trường `AGENT_API_KEY` trong dashboard.
- Nếu có giá trị mặc định `"changeme"`: Ứng dụng vẫn âm thầm khởi động bình thường. Kẻ xấu scan endpoint công khai sẽ dùng ngay key mặc định `"changeme"` để gọi API, bào mòn token LLM và làm cạn ngân sách tài khoản mà chủ hệ thống không hề hay biết cho đến khi nhận hóa đơn tiền triệu.
- Nếu không có mặc định (Fail Fast): Pydantic ném `ValidationError` ngay lúc nạp cấu hình và container dừng ngay lập tức. Hệ thống CI/CD hoặc Orchestrator cảnh báo Deployment Failed ngay từ giây đầu tiên, buộc developer phải vào set secret trước khi service đón bất kỳ request nào từ bên ngoài.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Dòng log JSON thu được:
`{"event": "ask_completed", "level": "info", "timestamp": "2026-09-29T03:28:43.123456+00:00", "user_id": "sv-test", "tokens_in": 15, "tokens_out": 42, "cost_usd": 0.00015}`

Hai việc làm được với log JSON:
1. **Lọc và cảnh báo tự động trên hệ thống giám sát (Datadog/CloudWatch/ELK)**: Có thể viết truy vấn tự động lọc chính xác `level == "error"` hoặc phát hiện các request có `cost_usd > 0.1` để kích hoạt webhook cảnh báo khẩn cấp tới Slack.
2. **Tổng hợp số liệu và vẽ Dashboard thời gian thực**: Trích xuất trường số liệu (`tokens_in`, `tokens_out`, `cost_usd`) theo `user_id` để vẽ biểu đồ tổng chi phí tiêu thụ theo giờ/ngày và tính toán chi phí trung bình trên mỗi người dùng mà không cần viết regex bóc tách chuỗi phức tạp.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | ~1.02 GB |
| Multi-stage | ~280 MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

Phần dung lượng chênh lệch (~740 MB) bao gồm:
1. Base image bản đầu dùng `python:3.11` đầy đủ (dựa trên Debian full với build-essential, gcc, git, header files...) nặng hơn ~700MB so với `python:3.11-slim`.
2. Stage builder trung gian chứa các cache pip, tarball wheel tạm thời khi tải về không bị sao chép sang stage runtime. Stage runtime chỉ chứa đúng thư viện đã cài đặt (`site-packages`), binary thực thi (`uvicorn`), và source code ứng dụng.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Khi sửa 1 ký tự trong `app/main.py`:
- Các layer từ đầu tới `RUN pip install`: được dùng lại hoàn toàn từ cache (`CACHED`), Docker không chạy lại việc tải và cài đặt thư viện.
- Layer `COPY . /app` và các lệnh phía sau (`RUN chown`, `CMD`): bị invalidate cache và phải chạy lại vì nội dung build context đã thay đổi.

Nếu đặt `COPY . .` lên TRƯỚC `RUN pip install`:
Bất kỳ khi nào sửa dù chỉ 1 ký tự code, layer `COPY . .` bị vô hiệu hóa cache, kéo theo toàn bộ các layer bên dưới (bao gồm `RUN pip install`) phải chạy lại từ đầu. Việc cài lại toàn bộ thư viện mất vài phút thay vì chỉ mất chưa tới 1 giây.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện:
1. Kẻ tấn công phát hiện một lỗ hổng trong code Python (ví dụ injection thực thi command hệ thống qua `subprocess` hoặc lỗ hổng thư viện parser).
2. Hacker lợi dụng lỗ hổng để kích hoạt shell bên trong container. Do container mặc định chạy quyền root (UID 0), hacker có toàn quyền root trong môi trường container (đọc mọi file, cài backdoor).
3. Hacker khai thác tiếp các lỗ hổng nhân Linux (kernel exploit) hoặc mount sai quyền socket `/var/run/docker.sock` để thoát khỏi container (container breakout). Vì UID trong container là 0 khớp với root UID 0 trên host, hacker lập tức nắm toàn quyền root trên máy chủ vật lý thật.

Lệnh `USER appuser` cắt đứt chuỗi tấn công ngay từ bước 2: Hacker chỉ có quyền của user thường bị giới hạn trong thư mục `/app`, không thể sửa file hệ thống của container, không có quyền can thiệp vào tiến trình khác, và không thể leo thang đặc quyền ra host khi breakout.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

Người dùng có thể gửi tối đa **20 request** trong 2 giây liên tiếp.
Cách đạt được: Người dùng gửi 10 request vào giây `10:00:59` (giây cuối cùng của phút thứ nhất). Đến đúng giây `10:01:00`, đồng hồ reset quota về 0. Người dùng gửi tiếp 10 request vào giây `10:01:01` (giây đầu tiên của phút thứ hai). Khoảng thời gian từ 10:00:59 đến 10:01:01 chỉ đúng 2 giây nhưng hệ thống đếm theo phút đồng hồ vẫn cho phép cả 20 request đi qua. Thuật toán sliding window của Redis Sorted Set tính chính xác khoảng cách thời gian `now - 60s` nên triệt tiêu hoàn toàn lỗ hổng này.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

Khác nhau:
- Rate limit bảo vệ **tính sẵn sàng của hạ tầng (Infrastructure Availability / Concurrency)** bằng cách giới hạn số lượng request trong một đơn vị thời gian (ví dụ 10 req/phút), không quan tâm request đó tốn bao nhiêu token/tiền.
- Cost guard bảo vệ **ngân sách tài chính (Financial Budget)** bằng cách giới hạn tổng số tiền chi tiêu tích lũy trong tháng (ví dụ 10.0 USD/tháng), không quan tâm tần suất gọi nhanh hay chậm.

Tình huống minh họa:
- *Rate limit cho qua nhưng Cost guard chặn*: User gửi chỉ 1 request/phút (rất chậm, qua rate limit), nhưng request đó kèm context khổng lồ 100k tokens khiến chi phí vượt quá ngân sách tháng -> Cost guard trả 402 Payment Required.
- *Cost guard cho qua nhưng Rate limit chặn*: User mới bắt đầu tháng, ngân sách còn nguyên 10 USD, nhưng gửi liên tiếp 30 request trong 5 giây -> Rate limit chặn với mã 429 Too Many Requests để tránh nghẽn server.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

Thứ tự sự kiện:
1. Giây 0: Redis gặp sự cố mạng hoặc restart. Liveness check `/health` gọi Redis bị timeout hoặc ném lỗi.
2. Giây 5 - 15: Orchestrator (Docker/Kubernetes) nhận thấy endpoint liveness probe thất bại liên tục (vượt quá ngưỡng `retries`).
3. Giây 15 - 30: Orchestrator kết luận cả 3 container agent đều đã "chết" và tiến hành kill + restart toàn bộ 3 container.
4. Khi khởi động lại, các container mới khởi tạo lại kiểm tra Redis vẫn chưa kết nối được nên tiếp tục fail liveness probe và bị restart tiếp.
5. Hậu quả: Toàn bộ cụm dịch vụ rơi vào vòng lặp crash liên hoàn (CrashLoopBackOff / Cascading Failure), người dùng hoàn toàn không nhận được phản hồi nào, trong khi bản thân ứng dụng Python không hề có lỗi code.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

- Hiện tượng khi dùng Redis: Cả 3 container agent đều đọc và ghi lịch sử hội thoại chung vào Redis, nên dù request sau được Load Balancer định tuyến ngẫu nhiên vào bất kỳ instance nào (A, B hay C), `history_length` luôn tăng đều đặn theo số lượt hỏi: 0 -> 2 -> 4 -> 6...
- Nếu lưu trong dict Python (Stateful): Mỗi instance có một vùng nhớ RAM tách biệt. User hỏi lần 1 vào A (`history_length = 0`). Lần 2 rơi vào B (`history_length` lại là 0 thay vì 2). Lần 3 rơi vào C (lại là 0). Lần 4 quay lại A (lúc này mới là 2). `history_length` sẽ nhảy lung tung giật cục và Agent trở nên "mất trí nhớ", trả lời câu sau mà không hề nhớ câu hỏi trước đó.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

- Lỗi gặp phải: Health check timeout dẫn đến deploy failed trên cloud platform (Railway/Render) với thông báo `Service failed to respond on port $PORT within 60s`.
- Cách tìm nguyên nhân: Mở tab Logs trên dashboard của platform, quan sát thấy Uvicorn báo đang lắng nghe ở cổng mặc định 8000 (`Uvicorn running on http://0.0.0.0:8000`), trong khi platform cấp phát biến môi trường `PORT=10000` và gửi probe kiểm tra vào cổng 10000.
- Cách sửa: Sửa lệnh CMD trong `Dockerfile` thành `CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]` để shell đọc biến môi trường `$PORT` do cloud chỉ định thay vì fix cứng cổng 8000.
