# MOD K8 Cloud Admin – bộ khởi tạo

## Có trong bộ file
- `index.html`: giao diện MOD K8 hiện tại.
- `admin.html`: trang Admin đăng nhập Supabase, nhập ACC hàng loạt, upload file lên Storage private, thêm sản phẩm link/tool và xem kho sản phẩm.
- `supabase/schema.sql`: cấu trúc database, RLS và bucket private.

## Cài đặt Supabase
1. Tạo project tại https://supabase.com.
2. Mở SQL Editor, chạy toàn bộ `supabase/schema.sql`.
3. Vào Authentication > Users, tạo tài khoản Admin đầu tiên.
4. Mở Table Editor > profiles, tìm UUID của tài khoản vừa tạo và chạy:
   `update public.profiles set role='admin' where id='UUID_CUA_BAN';`
5. Vào Project Settings > API, lấy Project URL và anon/public key.
6. Mở `admin.html`, thay:
   - `PASTE_SUPABASE_PROJECT_URL`
   - `PASTE_SUPABASE_ANON_KEY`
   Chỉ dùng anon/public key ở trình duyệt. TUYỆT ĐỐI không dùng service_role key ở đây.
7. Đưa `index.html` và `admin.html` lên Netlify. Truy cập `/admin.html` để vào trang quản trị.

## Cách nhập hàng
- ACC: tạo sản phẩm loại `acc` trước trong bảng `products`, sau đó chọn sản phẩm tại tab Nhập kho ACC. Mỗi dòng `.txt`: `username|password`.
- File: tab Upload FILE GAME, chọn file và nhập tên/giá/mô tả. File nằm trong bucket private `product-files`.
- Link/tool: nhập URL và thông tin sản phẩm ở tab Thêm LINK / TOOL.

## Giới hạn quan trọng của phiên bản này
Đây là bộ khởi tạo Admin kết nối Supabase, không phải hệ thống bán hàng hoàn thiện. Chức năng mua hàng trên trang cửa hàng hiện tại vẫn là demo; chưa có quy trình tạo đơn thật, webhook ngân hàng, khóa tồn kho đồng thời, giao ACC/file/link tự động và signed URL tải file theo đơn.
Muốn bật tự động giao thật, cần triển khai backend/Edge Functions:
1. Tạo đơn ở trạng thái `pending_payment` trên server; server tự tính giá và kiểm tra tồn kho.
2. Nhận webhook từ cổng thanh toán (ví dụ SePay) và xác minh chữ ký/secret, mã đơn, số tiền, trạng thái giao dịch.
3. Trong transaction database, chỉ ghi nhận thanh toán một lần (idempotency), khóa và lấy đúng số ACC hoặc tạo delivery cho file/link.
4. File: chỉ tạo signed URL thời hạn ngắn sau khi đơn đã `paid`; không trả public URL.
5. ACC: chỉ trả thông tin cho đúng chủ đơn trong trang đơn hàng; không đưa vào response công khai.
6. Không gửi mật khẩu game qua log, email, analytics hoặc query string. Chỉ lưu dữ liệu ACC mà bạn có quyền kinh doanh và được phép chuyển giao.

## Gợi ý kiểm tra trước khi mở bán
- Tạo tài khoản khách thử và xác nhận không thể truy cập `/admin.html` sau đăng nhập nếu role không phải admin.
- Thử upload file nhỏ, xác nhận file không thể mở bằng URL public.
- Nhập ACC thử không phải ACC khách hàng thật.
- Kiểm tra RLS bằng tài khoản khách.
- Cấu hình backup, giới hạn dung lượng/tệp, chính sách bảo mật và quy trình xóa dữ liệu.
