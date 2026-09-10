import 'package:flutter/material.dart';

/// Masaüstünde tıklanabilir öğelerin üzerinde el imleci.
///
/// Flutter 3.47 ile birlikte Material düğmeleri ve [InkWell], imleç olarak
/// [WidgetStateMouseCursor.adaptiveClickable] kullanıyor. Bu değer yalnızca
/// web'de el imlecine, masaüstünde (Windows dahil) ok imlecine çözümleniyor.
/// Uygulamanın gövdesi tıklanabilir kartlardan oluştuğu için burada eski
/// davranışa dönüyoruz: etkin öğede el, devre dışı öğede ok imleci.
///
/// Kullanımı: [InkWell.mouseCursor], [Chip.mouseCursor],
/// [DropdownButton.mouseCursor] gibi alanlara doğrudan verilebilir; tema
/// tarafındaki karşılığı [AppTheme] içinde ayarlanır.
const WidgetStateMouseCursor kClickable = WidgetStateMouseCursor.clickable;
