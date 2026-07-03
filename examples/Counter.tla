---------------------------- MODULE Counter ----------------------------
\* Smoke spec for rules_tla: a mod-3 counter. Finite, so TLC terminates.
\* Exercises both a safety INVARIANT and a liveness PROPERTY.
EXTENDS Naturals

VARIABLE x

Init == x = 0
Next == x' = (x + 1) % 3

\* Weak fairness on Next so the liveness property below actually holds.
Spec == Init /\ [][Next]_x /\ WF_x(Next)

\* Safety: x stays in range.
TypeOK == x \in 0..2

\* Liveness: the counter returns to 0 infinitely often.
ReturnsToZero == []<>(x = 0)
=============================================================================
