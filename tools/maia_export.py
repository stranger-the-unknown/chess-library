"""Maia3-5M ağırlıklarını uygulamanın okuduğu biçime dönüştürür.

Kullanım (PyTorch kurulu bir Python ile):

    python tools/maia_export.py <maia3-5m.pt> assets/maia/maia3-5m.bin

Ağırlıklar: https://huggingface.co/UofTCSSLab/Maia3-5M (maia3-5m.pt).
Kod ve model: https://github.com/CSSLab/maia3 (AGPL-3.0).

Çıktı yalnızca hamle olasılıkları için gereken tensörleri taşır (değer ve
düşünme süresi başlıkları dışarıda). Ağırlıklar 16 bit kayan noktaya
çevrilir; 421 gerçekçi konumda en büyük olasılık farkı ~0,001 çıktı.

Biçim:
    8 bayt   b'MAIA3W01'
    4 bayt   manifest uzunluğu (uint32, little-endian)
    N bayt   manifest (UTF-8 JSON): yapılandırma ve tensör listesi
    dolgu    veri 16 baytlık sınırdan başlar
    veri     float16, little-endian, manifestteki sırayla art arda
"""
import hashlib
import json
import struct
import sys

import numpy as np
import torch

MAGIC = b'MAIA3W01'

CONFIG = {
    'history': 8,
    'dim_emb': 128,
    'dim_vit': 256,
    'head_hid_dim': 256,
    'num_heads': 8,
    'num_blocks': 8,
    'mlp_dim': 512,
    'gab_gen_size': 64,
    'gab_intermediate_dim': 64,
    'elo_upper': 5000,
    # torch.nn.RMSNorm(eps=None) float32 için finfo(float32).eps kullanır.
    'rms_eps': float(np.finfo(np.float32).eps),
    'ln_eps': 1e-5,
    'moves': 4352,
}


def tensor_names(blocks):
    names = [
        'elo_embedding_low.weight',
        'elo_embedding_high.weight',
        'token_projection.weight',
        'token_projection.bias',
        'gab_shared_weight',
    ]
    for i in range(blocks):
        p = f'transformer.layers.{i}.'
        names += [
            p + 'self_attn.mha.in_proj_weight',
            p + 'self_attn.mha.out_proj.weight',
            p + 'self_attn.sm2.weight',
            p + 'self_attn.sm2.bias',
            p + 'self_attn.ln1.weight',
            p + 'self_attn.ln1.bias',
            p + 'self_attn.sm3.weight',
            p + 'self_attn.sm3.bias',
            p + 'self_attn.ln2.weight',
            p + 'self_attn.ln2.bias',
            p + 'linear1.weight',
            p + 'linear1.bias',
            p + 'linear2.weight',
            p + 'linear2.bias',
            p + 'norm1.weight',
            p + 'norm2.weight',
        ]
    names += [
        'transformer.norm.weight',
        'transformer.norm.bias',
        'proj_sq_from.weight',
        'proj_sq_to.weight',
        'promo_bias_proj.weight',
    ]
    return names


def main(src, dst):
    ckpt = torch.load(src, map_location='cpu', weights_only=True)
    state = ckpt['model_state_dict'] if 'model_state_dict' in ckpt else ckpt
    # Eski kayıtlarda "smolgen" adı geçiyor; güncel ad "gab".
    state = {k.replace('smolgen', 'gab'): v for k, v in state.items()}

    tensors = []
    chunks = []
    offset = 0
    for name in tensor_names(CONFIG['num_blocks']):
        if name not in state:
            raise SystemExit(f'eksik tensör: {name}')
        array = state[name].detach().cpu().numpy().astype('<f2')
        tensors.append({'name': name, 'shape': list(array.shape), 'offset': offset})
        chunks.append(array.tobytes(order='C'))
        offset += array.size

    manifest = json.dumps(
        {'config': CONFIG, 'dtype': 'f16', 'tensors': tensors},
        separators=(',', ':'),
    ).encode('utf-8')
    header = MAGIC + struct.pack('<I', len(manifest)) + manifest
    header += b'\0' * ((16 - len(header) % 16) % 16)

    with open(dst, 'wb') as out:
        out.write(header)
        for chunk in chunks:
            out.write(chunk)

    digest = hashlib.sha256(open(dst, 'rb').read()).hexdigest()
    print(f'{dst}: {offset} ağırlık, sha256 {digest}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
