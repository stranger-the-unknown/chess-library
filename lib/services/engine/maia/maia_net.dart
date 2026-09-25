import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Maia-3 (CSSLab, AGPL-3.0) sinir ağının Dart ile ileri geçişi.
///
/// Orijinal model PyTorch'ta çalışıyor (github.com/CSSLab/maia3,
/// `maia3/models.py`). Uygulamaya Python ya da yerel bir çalışma zamanı
/// koymamak için ağ burada yeniden yazıldı; ağırlıklar
/// `tools/maia_export.py` ile üretilen dosyadan okunuyor. Doğruluğu
/// `test/maia_test.dart` orijinal modelin çıktılarıyla karşılaştırıyor.
///
/// Mimari: 64 kare = 64 token. Her token son 8 konumun taş dizilimini
/// (8 × 12 tek-sıcak) ve iki Elo gömmesini taşıyor. Ardından 8 transformer
/// bloğu (dikkat puanlarına tahtanın geometrisinden türetilen bir yanlılık
/// ekleniyor, "GAB") ve kaynak × hedef kare çarpımından hamle puanları.
///
/// Bu dosya Flutter'a bağımlı değil: arka plan isolate'inde çalışıyor.
class MaiaConfig {
  final int history;
  final int dimEmb;
  final int dimVit;
  final int headHid;
  final int heads;
  final int blocks;
  final int mlpDim;
  final int gabGen;
  final int gabIntermediate;
  final int eloUpper;
  final double rmsEps;
  final double lnEps;

  const MaiaConfig({
    required this.history,
    required this.dimEmb,
    required this.dimVit,
    required this.headHid,
    required this.heads,
    required this.blocks,
    required this.mlpDim,
    required this.gabGen,
    required this.gabIntermediate,
    required this.eloUpper,
    required this.rmsEps,
    required this.lnEps,
  });

  factory MaiaConfig.fromJson(Map<String, dynamic> json) => MaiaConfig(
        history: json['history'] as int,
        dimEmb: json['dim_emb'] as int,
        dimVit: json['dim_vit'] as int,
        headHid: json['head_hid_dim'] as int,
        heads: json['num_heads'] as int,
        blocks: json['num_blocks'] as int,
        mlpDim: json['mlp_dim'] as int,
        gabGen: json['gab_gen_size'] as int,
        gabIntermediate: json['gab_intermediate_dim'] as int,
        eloUpper: json['elo_upper'] as int,
        rmsEps: (json['rms_eps'] as num).toDouble(),
        lnEps: (json['ln_eps'] as num).toDouble(),
      );

  /// Bir tokenın konum kısmının genişliği (geçmiş × 12 taş türü).
  int get boardDim => history * 12;
}

/// Dosyadan okunmuş ağırlıklar.
class MaiaWeights {
  final MaiaConfig config;
  final Map<String, Float32List> _tensors;

  MaiaWeights._(this.config, this._tensors);

  static const List<int> _magic = [77, 65, 73, 65, 51, 87, 48, 49]; // MAIA3W01

  /// `tools/maia_export.py` biçimini çözer. Bozuk dosyada
  /// [FormatException] fırlatır.
  factory MaiaWeights.parse(Uint8List bytes) {
    if (bytes.length < 12) throw const FormatException('maia: dosya kısa');
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException('maia: tanınmayan dosya');
      }
    }
    final data = ByteData.sublistView(bytes);
    final manifestLength = data.getUint32(8, Endian.little);
    final manifestEnd = 12 + manifestLength;
    if (manifestEnd > bytes.length) {
      throw const FormatException('maia: manifest yarım');
    }
    final manifest = jsonDecode(
      utf8.decode(bytes.sublist(12, manifestEnd)),
    ) as Map<String, dynamic>;
    if (manifest['dtype'] != 'f16') {
      throw const FormatException('maia: beklenmeyen veri türü');
    }
    final dataStart = (manifestEnd + 15) & ~15;
    final table = _halfTable();
    final tensors = <String, Float32List>{};
    for (final raw in manifest['tensors'] as List) {
      final entry = raw as Map<String, dynamic>;
      final shape = (entry['shape'] as List).cast<int>();
      final count = shape.fold<int>(1, (a, b) => a * b);
      final start = dataStart + (entry['offset'] as int) * 2;
      if (start + count * 2 > bytes.length) {
        throw const FormatException('maia: veri yarım');
      }
      final out = Float32List(count);
      for (var i = 0; i < count; i++) {
        out[i] = table[data.getUint16(start + i * 2, Endian.little)];
      }
      tensors[entry['name'] as String] = out;
    }
    return MaiaWeights._(
      MaiaConfig.fromJson(manifest['config'] as Map<String, dynamic>),
      tensors,
    );
  }

  Float32List operator [](String name) {
    final tensor = _tensors[name];
    if (tensor == null) throw StateError('maia: eksik tensör $name');
    return tensor;
  }

  /// 16 bit kayan noktanın bütün değerleri, 32 bite çevrilmiş.
  static Float32List _halfTable() {
    final table = Float32List(65536);
    for (var h = 0; h < 65536; h++) {
      final sign = (h & 0x8000) != 0 ? -1.0 : 1.0;
      final exponent = (h >> 10) & 0x1f;
      final fraction = h & 0x3ff;
      double value;
      if (exponent == 0) {
        value = fraction * math.pow(2, -24).toDouble();
      } else if (exponent == 31) {
        value = fraction == 0 ? double.infinity : double.nan;
      } else {
        value = (1 + fraction / 1024) * math.pow(2, exponent - 15).toDouble();
      }
      table[h] = sign * value;
    }
    return table;
  }
}

/// Ağın kendisi: bir konum geçmişi ve Elo'dan hamle puanları üretir.
class MaiaNet {
  final MaiaWeights w;
  final MaiaConfig c;

  /// Ağırlıklar yapılandırmayla uyuşmuyorsa [FormatException]: yanlış
  /// hamle üretmektense hiç kurulmasın (oyun Stockfish'e düşer).
  MaiaNet(this.w) : c = w.config {
    final d = c.dimVit;
    final inDim = c.boardDim + 2 * c.dimEmb;
    // SIMD döngüleri dörtlü vektörlerle yürüyor; kalan atlanırdı.
    for (final n in [inDim, d, c.mlpDim, c.gabIntermediate, c.gabGen]) {
      if (n <= 0 || n % 4 != 0) {
        throw FormatException('maia: boyut 4\'ün katı değil ($n)');
      }
    }
    if (c.heads <= 0 || d % c.heads != 0 || (d ~/ c.heads) % 4 != 0) {
      throw const FormatException('maia: başlık boyutu uygun değil');
    }
    final g = c.heads * c.gabGen;
    final expected = <String, int>{
      'token_projection.weight': d * inDim,
      'token_projection.bias': d,
      'elo_embedding_low.weight': c.dimEmb,
      'elo_embedding_high.weight': c.dimEmb,
      'gab_shared_weight': 4096 * c.gabGen,
      'transformer.norm.weight': d,
      'transformer.norm.bias': d,
      'proj_sq_from.weight': c.headHid * d,
      'proj_sq_to.weight': c.headHid * d,
      'promo_bias_proj.weight': 4 * c.headHid,
      for (var b = 0; b < c.blocks; b++) ...{
        'transformer.layers.$b.linear1.weight': c.mlpDim * d,
        'transformer.layers.$b.linear1.bias': c.mlpDim,
        'transformer.layers.$b.linear2.weight': d * c.mlpDim,
        'transformer.layers.$b.linear2.bias': d,
        'transformer.layers.$b.norm1.weight': d,
        'transformer.layers.$b.norm2.weight': d,
        'transformer.layers.$b.self_attn.mha.in_proj_weight': 3 * d * d,
        'transformer.layers.$b.self_attn.mha.out_proj.weight': d * d,
        'transformer.layers.$b.self_attn.sm2.weight': c.gabIntermediate * d,
        'transformer.layers.$b.self_attn.sm2.bias': c.gabIntermediate,
        'transformer.layers.$b.self_attn.ln1.weight': c.gabIntermediate,
        'transformer.layers.$b.self_attn.ln1.bias': c.gabIntermediate,
        'transformer.layers.$b.self_attn.sm3.weight': g * c.gabIntermediate,
        'transformer.layers.$b.self_attn.sm3.bias': g,
        'transformer.layers.$b.self_attn.ln2.weight': g,
        'transformer.layers.$b.self_attn.ln2.bias': g,
      },
    };
    expected.forEach((name, length) {
      final tensor = w._tensors[name];
      if (tensor == null || tensor.length != length) {
        throw FormatException('maia: $name eksik ya da yanlış boyutta');
      }
    });
  }

  /// Toplam hamle sözlüğü: 64 × 64 kare çifti + 8 × 8 × 4 terfi.
  static const int moveCount = 4096 + 256;

  /// [board]: 64 × [MaiaConfig.boardDim] tek-sıcak konum geçmişi (kare
  /// sırası a1 = 0; bkz. `maia_encoder.dart`). [moves]: istenen hamle
  /// numaraları. Dönen dizi aynı sırayla ham puanlar (logit).
  Float64List logits(
    Float32List board,
    int selfElo,
    int oppoElo,
    List<int> moves,
  ) {
    final x = _embed(board, selfElo, oppoElo);
    for (var b = 0; b < c.blocks; b++) {
      _block(x, 'transformer.layers.$b.');
    }
    _layerNorm(x, 64, c.dimVit, w['transformer.norm.weight'],
        w['transformer.norm.bias']);
    return _policy(x, moves);
  }

  // ---------------------------------------------------------------------
  // Katmanlar
  // ---------------------------------------------------------------------

  Float32List _embed(Float32List board, int selfElo, int oppoElo) {
    final boardDim = c.boardDim;
    final inDim = boardDim + 2 * c.dimEmb;
    final input = Float32List(64 * inDim);
    final self = _eloEmbedding(selfElo);
    final oppo = _eloEmbedding(oppoElo);
    for (var t = 0; t < 64; t++) {
      final row = t * inDim;
      for (var i = 0; i < boardDim; i++) {
        input[row + i] = board[t * boardDim + i];
      }
      for (var i = 0; i < c.dimEmb; i++) {
        input[row + boardDim + i] = self[i];
        input[row + boardDim + c.dimEmb + i] = oppo[i];
      }
    }
    final x = Float32List(64 * c.dimVit);
    _linear(input, 64, inDim, w['token_projection.weight'], c.dimVit,
        w['token_projection.bias'], x);
    return x;
  }

  /// Elo iki öğrenilmiş vektör arasında doğrusal karışım
  /// (`MAIA3Model.interpolate_elo`).
  Float32List _eloEmbedding(int elo) {
    final low = w['elo_embedding_low.weight'];
    final high = w['elo_embedding_high.weight'];
    final weightLow = elo.clamp(0, c.eloUpper) / c.eloUpper;
    final out = Float32List(c.dimEmb);
    for (var i = 0; i < c.dimEmb; i++) {
      out[i] = weightLow * low[i] + (1 - weightLow) * high[i];
    }
    return out;
  }

  /// Bir transformer bloğu: dikkat → artık + RMSNorm → ileri besleme →
  /// artık + RMSNorm (`EncoderOnlyBlock`, norm sonradan).
  void _block(Float32List x, String p) {
    final d = c.dimVit;
    final attention = _attention(x, p);
    for (var i = 0; i < x.length; i++) {
      x[i] += attention[i];
    }
    _rmsNorm(x, 64, d, w['${p}norm1.weight']);

    final hidden = Float32List(64 * c.mlpDim);
    _linear(x, 64, d, w['${p}linear1.weight'], c.mlpDim,
        w['${p}linear1.bias'], hidden);
    for (var i = 0; i < hidden.length; i++) {
      hidden[i] = _gelu(hidden[i]);
    }
    final ff = Float32List(64 * d);
    _linear(hidden, 64, c.mlpDim, w['${p}linear2.weight'], d,
        w['${p}linear2.bias'], ff);
    for (var i = 0; i < x.length; i++) {
      x[i] += ff[i];
    }
    _rmsNorm(x, 64, d, w['${p}norm2.weight']);
  }

  /// Çok başlı dikkat; puanlara GAB yanlılığı ekleniyor. Q, K, V ve çıkış
  /// izdüşümlerinde yanlılık terimi yok (`omit_qkv_biases`).
  Float32List _attention(Float32List x, String p) {
    final d = c.dimVit;
    final heads = c.heads;
    final headDim = d ~/ heads;
    final qkv = Float32List(64 * 3 * d);
    _linear(x, 64, d, w['${p}self_attn.mha.in_proj_weight'], 3 * d, null,
        qkv);
    final bias = _gabBias(x, p);

    final scale = 1 / math.sqrt(headDim);
    final concat = Float32List(64 * d);
    final scores = Float64List(64);
    // Dörtlü vektörlerle (başlık boyutu 32, satırlar 4'ün katı).
    final q4 = Float32x4List.view(qkv.buffer);
    final c4 = Float32x4List.view(concat.buffer);
    final row4 = (3 * d) >> 2;
    final head4 = headDim >> 2;
    for (var h = 0; h < heads; h++) {
      final qOff = (h * headDim) >> 2;
      final kOff = (d + h * headDim) >> 2;
      final vOff = (2 * d + h * headDim) >> 2;
      final biasOff = h * 4096;
      for (var i = 0; i < 64; i++) {
        final qi = i * row4 + qOff;
        var max = double.negativeInfinity;
        for (var j = 0; j < 64; j++) {
          final kj = j * row4 + kOff;
          var acc = Float32x4.zero();
          for (var e = 0; e < head4; e++) {
            acc += q4[qi + e] * q4[kj + e];
          }
          final s = (acc.x + acc.y + acc.z + acc.w) * scale +
              bias[biasOff + i * 64 + j];
          scores[j] = s;
          if (s > max) max = s;
        }
        var sum = 0.0;
        for (var j = 0; j < 64; j++) {
          final e = math.exp(scores[j] - max);
          scores[j] = e;
          sum += e;
        }
        final out = (i * d + h * headDim) >> 2;
        for (var j = 0; j < 64; j++) {
          final pj = Float32x4.splat(scores[j] / sum);
          final vj = j * row4 + vOff;
          for (var e = 0; e < head4; e++) {
            c4[out + e] += pj * q4[vj + e];
          }
        }
      }
    }
    final result = Float32List(64 * d);
    _linear(concat, 64, d, w['${p}self_attn.mha.out_proj.weight'], d, null,
        result);
    return result;
  }

  /// Geometrik dikkat yanlılığı (`MHA._sq_bias`, kare başına boyut 0):
  /// tokenların ortalaması → küçük bir ağ → başlık başına 64 × 64 yanlılık.
  Float32List _gabBias(Float32List x, String p) {
    final d = c.dimVit;
    final mean = Float32List(d);
    for (var t = 0; t < 64; t++) {
      for (var i = 0; i < d; i++) {
        mean[i] += x[t * d + i];
      }
    }
    for (var i = 0; i < d; i++) {
      mean[i] /= 64;
    }
    final mid = Float32List(c.gabIntermediate);
    _linear(mean, 1, d, w['${p}self_attn.sm2.weight'], c.gabIntermediate,
        w['${p}self_attn.sm2.bias'], mid);
    for (var i = 0; i < mid.length; i++) {
      mid[i] = _gelu(mid[i]);
    }
    _layerNorm(mid, 1, c.gabIntermediate, w['${p}self_attn.ln1.weight'],
        w['${p}self_attn.ln1.bias']);
    final gen = Float32List(c.heads * c.gabGen);
    _linear(mid, 1, c.gabIntermediate, w['${p}self_attn.sm3.weight'],
        gen.length, w['${p}self_attn.sm3.bias'], gen);
    for (var i = 0; i < gen.length; i++) {
      gen[i] = _gelu(gen[i]);
    }
    _layerNorm(gen, 1, gen.length, w['${p}self_attn.ln2.weight'],
        w['${p}self_attn.ln2.bias']);
    // (başlık, gen) × (4096, gen)ᵀ → (başlık, 4096)
    final bias = Float32List(c.heads * 4096);
    _linear(gen, c.heads, c.gabGen, w['gab_shared_weight'], 4096, null, bias);
    return bias;
  }

  /// İstenen hamlelerin puanları (`MAIA3Model.forward`, hamle başlığı).
  Float64List _policy(Float32List x, List<int> moves) {
    final d = c.dimVit;
    final hid = c.headHid;
    final from = Float32List(64 * hid);
    final to = Float32List(64 * hid);
    _linear(x, 64, d, w['proj_sq_from.weight'], hid, null, from);
    _linear(x, 64, d, w['proj_sq_to.weight'], hid, null, to);
    final root = math.sqrt(hid);
    final promo = w['promo_bias_proj.weight'];

    double pair(int a, int b) {
      var s = 0.0;
      for (var e = 0; e < hid; e++) {
        s += from[a * hid + e] * to[b * hid + e];
      }
      return s / root;
    }

    final out = Float64List(moves.length);
    for (var m = 0; m < moves.length; m++) {
      final index = moves[m];
      if (index < 4096) {
        out[m] = pair(index ~/ 64, index % 64);
      } else {
        // Terfi: 7. sıradan 8. sıraya; kaynak dosya, hedef dosya, taş.
        final k = index - 4096;
        final fromFile = k ~/ 32;
        final toFile = (k ~/ 4) % 8;
        final piece = k % 4;
        final toSquare = 56 + toFile;
        var promoBias = 0.0;
        for (var e = 0; e < hid; e++) {
          promoBias += to[toSquare * hid + e] * promo[piece * hid + e];
        }
        out[m] = pair(48 + fromFile, toSquare) + promoBias * root;
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Temel işlemler
  // ---------------------------------------------------------------------

  /// y[r, o] = Σ x[r, i] · W[o, i] (+ b[o]). W, PyTorch'taki gibi
  /// (çıkış, giriş) düzeninde. Dörtlü SIMD vektörleriyle.
  static void _linear(
    Float32List x,
    int rows,
    int inDim,
    Float32List weight,
    int outDim,
    Float32List? bias,
    Float32List y,
  ) {
    final n4 = inDim >> 2;
    final x4 = Float32x4List.view(x.buffer, x.offsetInBytes, rows * n4);
    final w4 = Float32x4List.view(
        weight.buffer, weight.offsetInBytes, outDim * n4);
    // İki satır × dört çıktı birlikte: tek toplayıcıyla her toplama bir
    // öncekini bekliyordu ve okunan her vektör bir kez kullanılıyordu.
    // Her çıktının toplama sırası aynı; sonuç bit bit aynı.
    final out4 = outDim & ~3;
    var r = 0;
    for (; r + 1 < rows; r += 2) {
      final xa = r * n4;
      final xb = xa + n4;
      final ya = r * outDim;
      final yb = ya + outDim;
      for (var o = 0; o < out4; o += 4) {
        final w0 = o * n4;
        final w1 = w0 + n4;
        final w2 = w1 + n4;
        final w3 = w2 + n4;
        var a0 = Float32x4.zero(), a1 = Float32x4.zero();
        var a2 = Float32x4.zero(), a3 = Float32x4.zero();
        var b0 = Float32x4.zero(), b1 = Float32x4.zero();
        var b2 = Float32x4.zero(), b3 = Float32x4.zero();
        for (var i = 0; i < n4; i++) {
          final va = x4[xa + i];
          final vb = x4[xb + i];
          final v0 = w4[w0 + i];
          final v1 = w4[w1 + i];
          final v2 = w4[w2 + i];
          final v3 = w4[w3 + i];
          a0 += va * v0;
          a1 += va * v1;
          a2 += va * v2;
          a3 += va * v3;
          b0 += vb * v0;
          b1 += vb * v1;
          b2 += vb * v2;
          b3 += vb * v3;
        }
        y[ya + o] = _sum(a0, bias, o);
        y[ya + o + 1] = _sum(a1, bias, o + 1);
        y[ya + o + 2] = _sum(a2, bias, o + 2);
        y[ya + o + 3] = _sum(a3, bias, o + 3);
        y[yb + o] = _sum(b0, bias, o);
        y[yb + o + 1] = _sum(b1, bias, o + 1);
        y[yb + o + 2] = _sum(b2, bias, o + 2);
        y[yb + o + 3] = _sum(b3, bias, o + 3);
      }
      for (var o = out4; o < outDim; o++) {
        y[ya + o] = _dot(x4, xa, w4, o * n4, n4, bias, o);
        y[yb + o] = _dot(x4, xb, w4, o * n4, n4, bias, o);
      }
    }
    for (; r < rows; r++) {
      final xr = r * n4;
      final yr = r * outDim;
      for (var o = 0; o < outDim; o++) {
        y[yr + o] = _dot(x4, xr, w4, o * n4, n4, bias, o);
      }
    }
  }

  static double _sum(Float32x4 acc, Float32List? bias, int o) {
    var sum = acc.x + acc.y + acc.z + acc.w;
    if (bias != null) sum += bias[o];
    return sum;
  }

  static double _dot(
    Float32x4List x4,
    int xr,
    Float32x4List w4,
    int wo,
    int n4,
    Float32List? bias,
    int o,
  ) {
    var acc = Float32x4.zero();
    for (var i = 0; i < n4; i++) {
      acc += x4[xr + i] * w4[wo + i];
    }
    return _sum(acc, bias, o);
  }

  void _rmsNorm(Float32List x, int rows, int dim, Float32List weight) {
    for (var r = 0; r < rows; r++) {
      final off = r * dim;
      var sq = 0.0;
      for (var i = 0; i < dim; i++) {
        final v = x[off + i];
        sq += v * v;
      }
      final inv = 1 / math.sqrt(sq / dim + c.rmsEps);
      for (var i = 0; i < dim; i++) {
        x[off + i] = x[off + i] * inv * weight[i];
      }
    }
  }

  void _layerNorm(
    Float32List x,
    int rows,
    int dim,
    Float32List weight,
    Float32List bias,
  ) {
    for (var r = 0; r < rows; r++) {
      final off = r * dim;
      var mean = 0.0;
      for (var i = 0; i < dim; i++) {
        mean += x[off + i];
      }
      mean /= dim;
      var variance = 0.0;
      for (var i = 0; i < dim; i++) {
        final v = x[off + i] - mean;
        variance += v * v;
      }
      final inv = 1 / math.sqrt(variance / dim + c.lnEps);
      for (var i = 0; i < dim; i++) {
        x[off + i] = (x[off + i] - mean) * inv * weight[i] + bias[i];
      }
    }
  }

  /// PyTorch'un varsayılan (erf tabanlı, kesin) GELU'su.
  static double _gelu(double x) => 0.5 * x * (1 + _erf(x * math.sqrt1_2));

  /// Hata fonksiyonu; mutlak hata < 1,2 × 10⁻⁷ (Numerical Recipes, erfc
  /// Chebyshev yaklaşımı).
  static double _erf(double x) {
    final z = x.abs();
    final t = 1 / (1 + 0.5 * z);
    final ans = t *
        math.exp(-z * z -
            1.26551223 +
            t *
                (1.00002368 +
                    t *
                        (0.37409196 +
                            t *
                                (0.09678418 +
                                    t *
                                        (-0.18628806 +
                                            t *
                                                (0.27886807 +
                                                    t *
                                                        (-1.13520398 +
                                                            t *
                                                                (1.48851587 +
                                                                    t *
                                                                        (-0.82215223 +
                                                                            t * 0.17087277)))))))));
    final erfc = x >= 0 ? ans : 2 - ans;
    return 1 - erfc;
  }
}
