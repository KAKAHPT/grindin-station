# SwissMatcher repete adversários (comportamento herdado do Canivete)

Data: 2026-10-14 · Origem: Task 6 (congelar o emparelhamento Swiss) · Teste afetado:
`test/jobs/tournaments/create_pods_job_test.rb` — "players never meet twice while another pairing is possible" (em `skip`).

## O que acontece

16 jogadores, ronda 1 com 4 pods de 4, todos os pods em empate (`Draw`). Existe um emparelhamento limpo para a
ronda 2 (um jogador de cada pod da ronda 1 por pod), mas o `CreatePodsJob` produz sempre reencontros.
Três execuções reais (números = "Jogador N", pela ordem dos assentos):

| Execução | Ronda 1 | Ronda 2 | Pares repetidos na R2 |
|---|---|---|---|
| 1 | P1[5,8,1,14] P2[13,9,10,12] P3[6,16,15,11] P4[2,3,4,7] | P1[11,15,9,13] P2[7,1,8,6] P3[12,10,2,5] P4[14,4,3,16] | 5 |
| 2 | P1[10,5,9,15] P2[1,11,6,2] P3[14,8,7,4] P4[12,3,16,13] | P1[15,4,5,14] P2[11,3,1,12] P3[13,2,8,10] P4[9,16,6,7] | 4 |
| 3 | P1[4,6,15,12] P2[9,11,5,10] P3[7,8,14,2] P4[16,13,1,3] | P1[2,3,13,11] P2[12,14,5,7] P3[15,8,6,9] P4[10,1,4,16] | 4 |

O cenário alternativo sugerido no plano (20 jogadores) também falha: a ronda 2 de 17–24 jogadores é `:spread`, e
deu 3, 2 e 4 pares repetidos em três execuções (ex.: R1 P1[9,3,18,5] … → R2 P1[1,3,8,4] P2[18,6,15,17] P3[5,19,7,13]
P4[10,12,16,14] P5[2,11,20,9]). Uma ronda `:forced` (25 jogadores, ronda 4, depois de 3 rondas de empates) deu 12 e
10 pares repetidos.

## Porquê (leitura do código, sem alterações)

- `Strategies::SwissMatcher#match!` usa `forced ? pod.receive_candidate : pod.force_candidate`. Nas rondas
  `:standard` (`forced: false`) chama `force_candidate`, que **ignora** `can_match?`; só as rondas `:forced` verificam
  reencontros. A condição parece invertida.
- `Strategies::SpreadMatcher` usa sempre `force_candidate` (serpentina por ranking, sem olhar a reencontros).
- Com todos empatados, `PlayerSorter` baralha e o `rank_score` é igual para todos, logo a ordem é aleatória.
- `Pod#can_match?` aceita qualquer candidato que já tenha jogado num pod de 3 (`played_in_smaller_pod?`), o que
  em torneios com pods de 3 desliga quase toda a proteção.
- `Pod#swap_suitable_by_rank_for?` compara a média de `rank_score` (ordem de 1e14) com `match_win_percentage ± 0.1`,
  portanto nunca é verdadeiro e `attempt_swaping!` nunca troca. (Se trocasse, `swap!` chamaria `pod.swap!`, que não
  existe — o método chama-se `swap_candidates!`; e `best_swap_candidate_by_rank_for` recebe 2 argumentos mas é
  chamado com 1.)

## Decisão pendente

Corrigir isto exige alterar `app/` (fora do âmbito da Task 6, que só acrescenta testes). O teste fica escrito e em
`skip`, a apontar para esta nota, até uma tarefa de correção do emparelhamento o reativar.
