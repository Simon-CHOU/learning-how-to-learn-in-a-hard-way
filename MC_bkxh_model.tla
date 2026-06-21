---- MODULE MC_bkxh_model ----
EXTENDS Naturals, Sequences, FiniteSets, TLC

(* Concrete model instance -- constants inlined for TLC model checking *)

Q1 == "q1"
K1 == "k1"
K2 == "k2"
P1 == "p1"
E1 == "e1"

QuestionSet == {Q1}
Knowledge  == {K1, K2}
Pattern    == {P1}
ErrorPoint == {E1}
QuestionPatternMap == [q \in QuestionSet |-> P1]
PatternInherentErrors == [p \in Pattern |-> {E1}]
MasteryThreshold == 80

VARIABLES
    learnerState,
    treeK2P,
    nodeMastery,
    currentQuestion

States   == {"Idle", "Retrieving", "Solving", "Consolidating", "Expanding"}
Vars     == <<learnerState, treeK2P, nodeMastery, currentQuestion>>
AllNodes == Knowledge \cup Pattern \cup ErrorPoint

Init ==
    /\ learnerState = "Idle"
    /\ treeK2P = [k \in Knowledge |-> [p \in Pattern |-> FALSE]]
    /\ nodeMastery = [n \in AllNodes |-> 0]
    /\ currentQuestion \in QuestionSet

StartRetrieving ==
    /\ learnerState = "Idle"
    /\ learnerState' = "Retrieving"
    /\ UNCHANGED <<treeK2P, nodeMastery, currentQuestion>>

GetRelatedNodes(q) ==
    LET targetP == QuestionPatternMap[q]
    IN <<targetP,
        {k \in Knowledge : treeK2P[k][targetP] = TRUE},
        PatternInherentErrors[targetP]>>

RetrieveSuccess ==
    /\ learnerState = "Retrieving"
    /\ LET related == GetRelatedNodes(currentQuestion)
           relatedK == related[2]
           relatedE == related[3]
       IN
           /\ relatedK # {}
           /\ \A k \in relatedK : nodeMastery[k] >= MasteryThreshold
           /\ \A e \in relatedE : nodeMastery[e] >= MasteryThreshold
    /\ learnerState' = "Solving"
    /\ UNCHANGED <<treeK2P, nodeMastery, currentQuestion>>

RetrieveFail ==
    /\ learnerState = "Retrieving"
    /\ LET related == GetRelatedNodes(currentQuestion)
           relatedK == related[2]
           relatedE == related[3]
       IN
           \/ relatedK = {}
           \/ \E k \in relatedK : nodeMastery[k] < MasteryThreshold
           \/ \E e \in relatedE : nodeMastery[e] < MasteryThreshold
    /\ learnerState' = "Expanding"
    /\ UNCHANGED <<treeK2P, nodeMastery, currentQuestion>>

SolveCorrectly ==
    /\ learnerState = "Solving"
    /\ learnerState' = "Consolidating"
    /\ UNCHANGED <<treeK2P, nodeMastery, currentQuestion>>

SolveIncorrectly ==
    /\ learnerState = "Solving"
    /\ learnerState' = "Expanding"
    /\ UNCHANGED <<treeK2P, nodeMastery, currentQuestion>>

Consolidate ==
    /\ learnerState = "Consolidating"
    /\ LET related == GetRelatedNodes(currentQuestion)
           nodesToBoost == related[2] \cup related[3] \cup {related[1]}
       IN
           /\ nodeMastery' = [n \in AllNodes |->
               IF n \in nodesToBoost THEN (IF nodeMastery[n] + 10 < 100 THEN nodeMastery[n] + 10 ELSE 100) ELSE nodeMastery[n]]
    /\ learnerState' = "Idle"
    /\ currentQuestion' \in QuestionSet
    /\ UNCHANGED treeK2P

ExpandTree ==
    /\ learnerState = "Expanding"
    /\ LET related == GetRelatedNodes(currentQuestion)
           targetP == related[1]
           relatedK == related[2]
           relatedE == related[3]
           weakK == {k \in relatedK : nodeMastery[k] < MasteryThreshold}
           weakE == {e \in relatedE : nodeMastery[e] < MasteryThreshold}
       IN
           \/ (/\ relatedK # {}
               /\ ( \/ (/\ (weakK # {} \/ weakE # {})
                        /\ nodeMastery' = [n \in AllNodes |->
                             IF n \in weakK \cup weakE
                             THEN (IF nodeMastery[n] + 30 < 100 THEN nodeMastery[n] + 30 ELSE 100)
                             ELSE nodeMastery[n]]
                     )
                   \/ (/\ weakK = {}
                        /\ weakE = {}
                        /\ UNCHANGED nodeMastery
                     )
                  )
               /\ UNCHANGED treeK2P
              )

           \/ (/\ relatedK = {}
               /\ \E k1 \in Knowledge : \E k2 \in Knowledge :
                    /\ k1 # k2
                    /\ treeK2P' = [k \in Knowledge |->
                                  IF k = k1 \/ k = k2
                                  THEN [treeK2P[k] EXCEPT ![targetP] = TRUE]
                                  ELSE treeK2P[k]]
               /\ UNCHANGED nodeMastery
              )

    /\ learnerState' = "Idle"
    /\ currentQuestion' \in QuestionSet

Next ==
    \/ StartRetrieving
    \/ RetrieveSuccess
    \/ RetrieveFail
    \/ SolveCorrectly
    \/ SolveIncorrectly
    \/ Consolidate
    \/ ExpandTree

ChangeTo(q) == currentQuestion' = q

Spec == Init /\ [][Next]_Vars
          /\ WF_<<learnerState>>(StartRetrieving)
          /\ WF_<<learnerState>>(RetrieveSuccess)
          /\ WF_<<learnerState>>(RetrieveFail)
          /\ WF_<<learnerState>>(SolveCorrectly)
          /\ WF_<<learnerState>>(SolveIncorrectly)
          /\ WF_<<learnerState>>(Consolidate)
          /\ WF_<<learnerState>>(ExpandTree)
          /\ \A q \in QuestionSet : WF_<<currentQuestion>>(ChangeTo(q))

TypeInvariant ==
    /\ learnerState \in States
    /\ treeK2P \in [Knowledge -> [Pattern -> BOOLEAN]]
    /\ nodeMastery \in [AllNodes -> 0..100]
    /\ currentQuestion \in QuestionSet

ExamPatterns == {QuestionPatternMap[q] : q \in QuestionSet}

StrongEnough ==
    \A p \in ExamPatterns :
        LET relatedK == {k \in Knowledge : treeK2P[k][p] = TRUE}
            inherentE == PatternInherentErrors[p]
        IN  /\ relatedK # {}
            /\ \A k \in relatedK : nodeMastery[k] >= MasteryThreshold
            /\ \A e \in inherentE : nodeMastery[e] >= MasteryThreshold

EventuallyPassExam == <>[] StrongEnough

=============================================================================
