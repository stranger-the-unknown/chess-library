"""Maia3 Dart gerçekleştirmesi için referans çıktılar üretir.

Kullanım:

    python tools/maia_reference.py <maia3 kaynak klasörü> <maia3-5m.pt> \
        test/fixtures/maia3_reference.json

Orijinal Python modeli (github.com/CSSLab/maia3) ağırlıkları uygulamadaki
gibi 16 bite yuvarlanmış hâlde çalıştırılır. Her konum için geçmiş (FEN
listesi, eskiden yeniye), Elo ve yasal hamlelerin en olası ilk 12'si
olasılıklarıyla yazılır. Dart testi aynı girdiden aynı olasılıkları
üretmeli.
"""
import json
import random
import sys
from argparse import Namespace
from collections import deque

import chess
import torch

SRC, WEIGHTS, OUT = sys.argv[1:4]
sys.path.insert(0, SRC)
from maia3.dataset import get_historical_tokens, get_legal_moves_mask, tokenize_board  # noqa: E402
from maia3.model_registry import resolve_model_spec  # noqa: E402
from maia3.uci import load_model  # noqa: E402
from maia3.utils import get_all_possible_moves, mirror_move  # noqa: E402

spec = resolve_model_spec('maia3-5m')
cfg = Namespace(**spec.config)
cfg.device = 'cpu'
cfg.checkpoint_path = WEIGHTS
cfg.trust_checkpoint = False
model = load_model(cfg)
with torch.no_grad():
    for p in model.parameters():
        p.copy_(p.half().float())

all_moves = get_all_possible_moves()
move_index = {m: i for i, m in enumerate(all_moves)}


def policy(boards, self_elo, oppo_elo):
    history = deque(maxlen=cfg.history)
    for b in boards[-cfg.history:]:
        history.append(tokenize_board(b))
    tokens = get_historical_tokens(history, cfg, 0.0, 0.0, 0.0, 0.0).unsqueeze(0)
    with torch.no_grad():
        logits, _, _ = model(tokens, torch.tensor([self_elo]), torch.tensor([oppo_elo]))
    mask = get_legal_moves_mask(boards[-1], move_index)
    return torch.softmax(logits[0].masked_fill(~mask, float('-inf')), -1)


def to_uci(board, index):
    uci = all_moves[index]
    return mirror_move(uci) if board.turn == chess.BLACK else uci


def record(boards, self_elo, oppo_elo):
    probs = policy(boards, self_elo, oppo_elo)
    top_p, top_i = torch.topk(probs, min(12, int((probs > 0).sum())))
    return {
        'history': [b.fen() for b in boards[-cfg.history:]],
        'selfElo': self_elo,
        'oppoElo': oppo_elo,
        'moves': [
            [to_uci(boards[-1], i), round(p, 6)]
            for p, i in zip(top_p.tolist(), top_i.tolist())
        ],
    }


cases = []
rng = random.Random(2026)
torch.manual_seed(2026)

# 1) Maia'nın kendisiyle oynanmış gerçekçi oyunlardan konumlar.
for game in range(24):
    elo = rng.choice([700, 1100, 1500, 1900, 2300])
    board = chess.Board()
    boards = [board.copy()]
    for ply in range(rng.randint(6, 70)):
        if board.is_game_over():
            break
        probs = policy(boards, elo, elo)
        board.push_uci(to_uci(board, int(torch.multinomial(probs, 1))))
        boards.append(board.copy())
        if ply % 9 == 5 and not board.is_game_over():
            cases.append(record(boards, rng.choice([800, 1200, 1600, 2000, 2400]),
                                rng.choice([800, 1500, 2200])))

# 2) Özel durumlar: geçmişsiz (tek konum) FEN'ler.
special = [
    chess.STARTING_FEN,
    # Rok iki yöne de açık, beyaz oynar / siyah oynar.
    'r3k2r/pppq1ppp/2npbn2/4p3/4P3/2NPBN2/PPPQ1PPP/R3K2R w KQkq - 4 9',
    'r3k2r/pppq1ppp/2npbn2/4p3/4P3/2NPBN2/PPPQ1PPP/R3K2R b KQkq - 4 9',
    # Geçerken alma.
    'rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3',
    'rnbqkbnr/pppp1ppp/8/8/3Pp3/5N2/PPP1PPPP/RNBQKB1R b KQkq d3 0 3',
    # Terfi: beyaz ve siyah, alarak terfi dahil.
    '1r5k/2P5/8/8/8/8/5K2/8 w - - 0 1',
    '8/5k2/8/8/8/8/2p5/1R5K b - - 0 1',
    # Şah altında.
    'rnbqkbnr/ppp2ppp/8/1B1pp3/4P3/8/PPPP1PPP/RNBQK1NR b KQkq - 1 3',
    # Oyun sonu.
    '8/8/4k3/8/2K5/8/3P4/8 w - - 0 1',
]
for fen in special:
    for elo in (900, 1700, 2500):
        cases.append(record([chess.Board(fen)], elo, elo))

with open(OUT, 'w', encoding='utf-8') as f:
    json.dump({'model': 'maia3-5m', 'weights': 'f16', 'cases': cases}, f,
              ensure_ascii=False, separators=(',', ':'))
print(f'{OUT}: {len(cases)} konum')
