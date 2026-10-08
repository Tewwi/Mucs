# Hướng Dẫn Quản Lý, Chỉnh Sửa & Tạo Mới Foliage (Cây & Đá)

Tài liệu này hướng dẫn chi tiết cách tạo mới, chỉnh sửa thông số và lưu các tài nguyên Foliage (`.tres`) cho hệ thống **MultiMesh Foliage System** trong dự án **Mucs**.

---

## 1. Cấu Trúc Hệ Thống Foliage

Hệ thống Foliage bao gồm 2 thành phần chính:
1. **`FoliageItemType`** (`scripts/foliage_item_type.gd`): Custom Resource định nghĩa toàn bộ thuộc tính của 1 loại vật thể (Mesh, va chạm, tầm nhìn, luật spawn, độ dốc, độ lún).
2. **`FoliageManager`** (`scripts/foliage_manager.gd`): Node quản lý trên Scene, chứa danh sách các `FoliageItemType`, tự động sinh `MultiMeshInstance3D` trên GPU và quản lý Proximity Collider Pool quanh Player.

Các file cấu hình được lưu trong thư mục:
```text
res://resources/foliage/
├── pine_tree.tres         # Cây thông
├── rock_medium.tres       # Tảng đá vừa
└── tree_broadleaf.tres    # Cây tán rộng
```

---

## 2. Cách Tạo Một Foliage Mới (.tres)

Có 2 cách để tạo một loại cây hoặc đá mới:

### Cách 1: Tạo từ Scene có sẵn (Khuyên dùng - Nhanh nhất)
Nếu bạn đã có sẵn 1 Scene `.tscn` của cây/đá (chứa `MeshInstance3D` và `CollisionShape3D`):

1. Trong tab **FileSystem** của Godot, chuột phải vào thư mục `res://resources/foliage/` -> Chọn **Create New -> Resource...**.
2. Tìm kiếm và chọn class **`FoliageItemType`**, đặt tên file (ví dụ: `bush_small.tres` hoặc `rock_large.tres`).
3. Mở file `.tres` vừa tạo, trong bảng **Inspector**:
   - Tìm mục **Auto-Extract from Scene** -> Kéo thả file Scene `.tscn` của bạn vào ô **Source Scene**.
   - Script sẽ **tự động bóc tách**:
     - Mesh 3D
     - Material override (nếu có)
     - Collision Shape (Capsule / Cylinder / Box)
     - Collision Offset (tọa độ lệch tâm)
4. Điều chỉnh thêm các thông số spawn (xem mục 3).
5. Nhấn `Ctrl + S` để lưu file.

---

### Cách 2: Nhân bản (Duplicate) từ file có sẵn
Nếu vật thể mới có tính chất tương tự cây hoặc đá đã có:

1. Trong tab **FileSystem**, chuột phải vào file tương tự (ví dụ: `pine_tree.tres` hoặc `rock_medium.tres`) -> Chọn **Duplicate...**.
2. Đổi tên thành file mới (ví dụ: `pine_snow.tres`).
3. Mở file mới lên và thay đổi:
   - **Mesh**: Kéo mesh mới vào ô `Mesh`.
   - **Noise**: Chuột phải vào ô `Noise` -> chọn *Make Unique* (hoặc đổi `Seed` khác) để phân bố vị trí không bị trùng với cây cũ.
   - **Collision Shape**: Nếu kích thước khác, chỉnh lại `radius` và `height`.
4. Nhấn `Ctrl + S` để lưu.

---

## 3. Hướng Dẫn Chi Tiết Các Thông Số Trong Inspector

| Nhóm | Tên Thông Số | Ý Nghĩa & Khuyến Nghị Giá Trị |
| :--- | :--- | :--- |
| **Định danh** | `name` | Tên hiển thị (ví dụ: `"Pine Tree"`, `"Rock Medium"`). |
| **Visual** | `mesh` | File ArrayMesh 3D của vật thể. |
| | `material_override` | *(Tùy chọn)* Ghi đè Material nếu muốn đổi màu/texture. |
| **Visibility Range** | `visibility_range_end` | **Khoảng cách tối đa nhìn thấy** (mét).<br>• Cây to: `60.0` - `80.0`<br>• Đá/bụi nhỏ: `30.0` - `40.0`<br>*(Vượt quá khoảng cách này GPU sẽ tự ẩn để tối ưu FPS)*. |
| | `visibility_range_end_margin` | Khoảng đệm mờ dần (Fade out margin, ví dụ `9.0`m). |
| **Physics** | `collision_shape` | Shape va chạm (`CapsuleShape3D` hoặc `CylinderShape3D`). Để trống nếu không cần va chạm (như cỏ, hoa). |
| | `collision_offset` | Độ lệch tâm của collider so với gốc tọa độ mesh (trục Y nâng lên một nửa chiều cao). |
| **Orientation** | `align_to_normal` | **Độ ôm nghiêng theo sườn dốc địa hình** [0.0 - 1.0]:<br>• Cây cối: `0.0` (luôn mọc thẳng đứng hướng lên trời).<br>• Đá/bụi cỏ: `0.8` - `1.0` (nghiêng tự nhiên theo sườn đồi). |
| **Spawn Rules** | `noise` | `FastNoiseLite` điều khiển vùng mọc (đổi `seed` để đổi vị trí). |
| | `noise_threshold` | Ngưỡng mọc [0.0 - 1.0]: Càng cao thì mọc càng thưa / co cụm. |
| | `min_slope` & `max_slope` | **Độ dốc địa hình** (`1.0` là đất phẳng, `0.0` là vách đứng 90°):<br>• Cây: `min_slope = 0.85`, `max_slope = 1.0` (chỉ mọc chỗ thoai thoải).<br>• Đá: `min_slope = 0.0`, `max_slope = 0.8` (mọc ở sườn đồi, vách dốc). |
| | `y_offset` | **Độ lún xuống đất** (giá trị âm):<br>• Cây: `-0.2` đến `-0.3` (cắm gốc nhẹ).<br>• Đá: `-0.8` đến `-1.0` (chìm 30-40% tránh hở đáy sườn dốc). |
| | `min_scale` / `max_scale` | Giới hạn tỉ lệ to nhỏ ngẫu nhiên (ví dụ: `0.8` - `1.3`). |
| | `max_count` | Số lượng cá thể tối đa được phép sinh trên toàn bản đồ. |

---

## 4. Cách Gán Foliage Mới Vào Game

Sau khi đã tạo và lưu file `.tres`, bạn cần gán nó vào **FoliageManager**:

1. Trong tab **Scene** của Godot, mở Scene chính (ví dụ: `game.scn` hoặc scene chứa địa hình).
2. Chọn node **`FoliageManager`** (thường nằm dưới `Terrain`).
3. Nhìn sang tab **Inspector** bên phải:
   - Tìm mục **Foliage Types** (dạng mảng `Array[FoliageItemType]`).
   - Tăng kích thước mảng (hoặc nhấn **Add Element**).
   - Kéo file `.tres` mới của bạn từ FileSystem thả vào ô phần tử mới đó.
4. Chạy game (`F5`): Hệ thống sẽ tự động khởi tạo MultiMesh và Collider pool cho vật thể mới ngay lập tức.

---

## 5. Những Lỗi Thường Gặp & Cách Khắc Phục

### Đá / Cây bị lơ lửng, hở chân trên dốc:
- **Khắc phục**: Mở file `.tres`, chỉnh `y_offset` âm nhiều hơn (ví dụ từ `-0.4` đổi thành `-0.85`). Với đá, đảm bảo `align_to_normal` đặt từ `0.8` trở lên.

### Cây mọc vào vách núi thẳng đứng:
- **Khắc phục**: Tăng `min_slope` của cây lên `>= 0.85` (trong Godot, giá trị gần 1.0 là đất phẳng).

### Va chạm không khớp với hình dáng cây:
- **Khắc phục**: Kiểm tra lại `collision_offset` trong file `.tres`. Nếu cây cao 8m thì `collision_offset.y` nên ở khoảng `4.0m` (tâm của capsule).
