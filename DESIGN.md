# Pull Kanban — Design (QFD)

This document designs the Pull Kanban app: how a team designs its Value Stream and then runs its daily work in it, with pull, Takt Time and Heijunka. It does not define terms: every term in **bold** is defined in [CONTEXT.md](./CONTEXT.md). Decisions that are hard to reverse go in [docs/adr/](./docs/adr/).

Strength weights used in matrices: **9** strong, **3** medium, **1** weak, blank none.

---

## House of Quality

The at-a-glance view of the design: the 10 Goals (§1) against 11 key Functions (§2) chosen for their cross-cutting weight, with the roof conflicts (§6) and the derived weights (§5).

```tikz
% =====================================================================
% QFD "House of Quality" preamble
% =====================================================================
% Usage:
%   \begin{document}
%   \begin{qfdhouse}
%     % WHATs at ({\qfdLeftEdge + 0.1}, {-\r + 0.5})
%     % Importance at ({-\qfdImpW/2}, {-\r + 0.5})
%     % HOWs rotated 90 at ({\c - 0.5}, 0.15)
%     % Relations in cells with [qfdrel/S], [qfdrel/M], [qfdrel/W]
%     % Roof correlations at (C-i-j)
%     % Perception markers at ({\qfdNH + (s+0.5)*\qfdCmpW/6}, {-\r + 0.5})
%     % Basement: target / difficulty / abs weight / rel weight, per HOW
%   \end{qfdhouse}
%   \end{document}
%
% NB: in node text, use $<$ / $>$ for less-than / greater-than under
% OT1 encoding; bare < and > render as Spanish ¡ ¿.
% =====================================================================

\usetikzlibrary{arrows.meta, positioning, shapes.geometric, shapes.misc, calc, fit, backgrounds}

% Toggles — flip before \begin{qfdhouse} to hide sections.
\newif\ifqfdshowroof          \qfdshowrooftrue
\newif\ifqfdshowbasement      \qfdshowbasementtrue
\newif\ifqfdshowcompetitive   \qfdshowcompetitivetrue
\newif\ifqfdshowlegend        \qfdshowlegendtrue
\newif\ifqfdshowimportance    \qfdshowimportancetrue
\newif\ifqfdshowcorrlegend    \qfdshowcorrlegendtrue
\newif\ifqfdshowevallegend    \qfdshowevallegendtrue
\newif\ifqfdshowtitle         \qfdshowtitletrue   % title block above the roof

% Dimensions — override before \begin{qfdhouse} to resize.
\def\qfdNW{5}           % number of WHATs (rows)
\def\qfdNH{5}           % number of HOWs (columns)
\def\qfdWhatW{4.0}      % width of WHATs column
\def\qfdImpW{0.9}       % width of importance column
\def\qfdCmpW{3}         % width of perception zone
\def\qfdHdrH{2.6}       % height of column-titles band
\def\qfdBasementN{4}    % number of basement rows

% Titles & labels — override before \begin{qfdhouse}.
\def\qfdWhatsTitle{Customer needs}
\def\qfdImpTitle{Imp.\ \%}
\def\qfdPerceptionTitle{Comparative evaluation}
\def\qfdPoorLabel{poor}
\def\qfdExcellentLabel{excellent}
\def\qfdAltOneLabel{Our product}    % highlighted in legend
\def\qfdAltTwoLabel{Competitor A}
\def\qfdAltThreeLabel{Competitor B}
\def\qfdRelTitle{Relation}
\def\qfdCorrTitle{Correlation}
\def\qfdEvalTitle{Evaluation}

% Title block above the roof — set both to name the house. Leave
% \qfdProjectTitle empty (default) to draw no title at all.
\def\qfdProjectTitle{}  % project / feature name (large, bold)
\def\qfdConcept{}       % concept in one sentence; \textbf{} the keywords

% Styles.
\tikzset{
  qfdthin/.style ={line width=0.35pt},
  qfdmed/.style  ={line width=0.7pt},
  qfdstrong/.style={circle, draw, fill=black,
                    minimum size=7pt, inner sep=0pt},
  qfdmod/.style  ={circle, draw,
                    minimum size=7pt, inner sep=0pt, line width=0.8pt},
  qfdweak/.style ={regular polygon, regular polygon sides=3, draw,
                    minimum size=8.5pt, inner sep=0pt, line width=0.7pt},
  qfdrel/.is choice,
  qfdrel/S/.style={qfdstrong},
  qfdrel/M/.style={qfdmod},
  qfdrel/W/.style={qfdweak},
  % Three perception-zone alternatives. Index 1 is emphasised.
  qfdalt1mk/.style={circle, draw, fill=black,
                    minimum size=6pt, inner sep=0pt, line width=1pt},
  qfdalt1ln/.style={line width=1.2pt},
  qfdalt2mk/.style={regular polygon, regular polygon sides=3, draw,
                    fill=black, minimum size=6pt, inner sep=0pt,
                    line width=0.7pt},
  qfdalt2ln/.style={line width=0.7pt, dashed},
  qfdalt3mk/.style={rectangle, draw, fill=black,
                    minimum size=5pt, inner sep=0pt, line width=0.7pt},
  qfdalt3ln/.style={line width=0.7pt, dotted},
}

% --- Grid lines for every zone. ---
\newcommand{\qfdDrawGrid}{%
  \foreach \c in {1,...,\qfdNHm} \draw[qfdthin] (\c, 0) -- (\c, -\qfdNW);
  \foreach \r in {1,...,\qfdNWm} \draw[qfdthin] (0, -\r) -- (\qfdNH, -\r);
  \foreach \r in {1,...,\qfdNWm}
    \draw[qfdthin] (\qfdLeftEdge, -\r) -- (0, -\r);
  \ifqfdshowroof
    \foreach \c in {1,...,\qfdNHm}
      \draw[qfdthin] (\c, 0) -- (\c, \qfdHdrH);
  \fi
  \ifqfdshowcompetitive
    \foreach \r in {1,...,\qfdNWm}
      \draw[qfdthin] (\qfdNH, -\r) -- (\qfdNH+\qfdCmpW, -\r);
  \fi
  \ifqfdshowbasement
    \foreach \r in {1,...,\qfdBasementN}
      \draw[qfdthin] (0, -\qfdNW-\r) -- (\qfdNH, -\qfdNW-\r);
    \foreach \c in {1,...,\qfdNHm}
      \draw[qfdthin] (\c, -\qfdNW) -- (\c, -\qfdNW-\qfdBasementN);
  \fi
}

% --- Roof: diagonal grid + named coordinates (C-i-j) for correlations. ---
\newcommand{\qfdDrawRoof}{%
  \ifqfdshowroof
    \foreach \k in {1,...,\qfdNHm} {%
      \pgfmathsetmacro{\rx}{(\k+\qfdNH)/2}
      \pgfmathsetmacro{\ry}{\qfdHdrH + (\qfdNH-\k)/2}
      \pgfmathsetmacro{\lx}{\k/2}
      \pgfmathsetmacro{\ly}{\qfdHdrH + \k/2}
      \draw[qfdthin] (\k, \qfdHdrH) -- (\rx, \ry);
      \draw[qfdthin] (\k, \qfdHdrH) -- (\lx, \ly);
    }%
    \draw[qfdmed] (0, \qfdHdrH)
       -- (\qfdNH/2, \qfdApexY) -- (\qfdNH, \qfdHdrH);
    \foreach \i in {1,...,\qfdNH}
      \foreach \k in {1,...,\qfdNH} {%
        \pgfmathtruncatemacro{\jj}{\i+\k}
        \ifnum\jj>\qfdNH\relax\else
          \pgfmathsetmacro{\xx}{\i + \k/2 - 0.5}
          \pgfmathsetmacro{\yy}{\qfdHdrH + \k/2}
          \coordinate (C-\i-\jj) at (\xx, \yy);
        \fi
      }%
  \fi
}

% --- Perception scale 0..5 + poor/excellent endpoints + zone title. ---
\newcommand{\qfdDrawScale}{%
  \ifqfdshowcompetitive
    \foreach \tk in {0,1,2,3,4,5} {%
      \pgfmathsetmacro{\tx}{\qfdNH + (\tk+0.5)*\qfdCmpW/6}
      \node[anchor=south, font=\scriptsize] at (\tx, 0.02) {\tk};
    }%
    \node[anchor=south, font=\scriptsize\bfseries, align=center]
         at ({\qfdNH + \qfdCmpW/2}, 0.7) {\qfdPerceptionTitle};
    \node[anchor=north, font=\scriptsize\itshape]
         at ({\qfdNH + 0.45}, -\qfdNW) {\qfdPoorLabel};
    \node[anchor=north, font=\scriptsize\itshape]
         at ({\qfdNH + \qfdCmpW - 0.45}, -\qfdNW) {\qfdExcellentLabel};
  \fi
}

% --- Importance title (left) and WHATs title (header band). ---
\newcommand{\qfdDrawZoneTitles}{%
  \ifqfdshowimportance
    \node[rotate=90, anchor=west, font=\footnotesize\bfseries]
         at ({-\qfdImpW/2}, 0.12) {\qfdImpTitle};
  \fi
  \node[font=\scriptsize\bfseries, align=center, text width=\qfdWhatW cm]
       at ({\qfdLeftEdge + \qfdWhatW/2},
           {\ifqfdshowroof \qfdHdrH/2 \else 0.6 \fi}) {\qfdWhatsTitle};
}

% --- Title + concept subtitle, centred above the roof apex. ---
\newcommand{\qfdDrawTitle}{%
  \ifqfdshowtitle
    \ifx\qfdProjectTitle\empty\else
      \pgfmathsetmacro{\qfdTitleX}{\qfdNH/2}
      \pgfmathsetmacro{\qfdTitleY}{\ifqfdshowroof \qfdApexY \else \qfdHdrH \fi + 0.9}
      \pgfmathsetmacro{\qfdSubW}{\qfdNH + 2}    % pre-computed (braces don't do arithmetic)
      \node[anchor=south, font=\large\bfseries, align=center]
           at (\qfdTitleX, \qfdTitleY) {\qfdProjectTitle};
      \ifx\qfdConcept\empty\else
        \node[anchor=north, font=\footnotesize\itshape, align=center,
              text width=\qfdSubW cm]
             at (\qfdTitleX, {\qfdTitleY - 0.1}) {\qfdConcept};
      \fi
    \fi
  \fi
}

% --- Outer frames around each zone. ---
\newcommand{\qfdDrawFrames}{%
  \begin{scope}[qfdmed]
    \draw (\qfdLeftEdge, 0) rectangle (\qfdNH, -\qfdNW);
    \ifqfdshowimportance \draw (-\qfdImpW, 0) -- (-\qfdImpW, -\qfdNW); \fi
    \draw (0, 0) -- (0, -\qfdNW);
    \ifqfdshowroof
      \draw (0, 0) rectangle (\qfdNH, \qfdHdrH); \fi
    \ifqfdshowbasement
      \draw (0, -\qfdNW) rectangle (\qfdNH, -\qfdNW-\qfdBasementN); \fi
    \ifqfdshowcompetitive
      \draw (\qfdNH, 0) rectangle (\qfdNH+\qfdCmpW, -\qfdNW); \fi
  \end{scope}
}

% --- Legend on the right (Relations / Correlations / Evaluation). ---
\newcommand{\qfdDrawLegend}{%
  \ifqfdshowlegend
    \pgfmathsetmacro{\qfdLegX}{%
      \qfdNH + \ifqfdshowcompetitive \qfdCmpW + 0.7 \else 0.7 \fi}
    \pgfmathsetmacro{\qfdLegBottom}{%
      -2.05
      \ifqfdshowroof    \ifqfdshowcorrlegend - 2.55 \fi \fi
      \ifqfdshowcompetitive \ifqfdshowevallegend - 2.20 \fi \fi}
    \pgfmathsetmacro{\qfdLegY}{\qfdHdrH - 0.4}
    \begin{scope}[shift={(\qfdLegX, \qfdLegY)}]
      \draw[qfdmed, rounded corners=2pt]
        (-0.15, 0.4) rectangle (4.5, \qfdLegBottom);
      % Relations
      \node[anchor=west, font=\footnotesize\bfseries] at (0, 0.1)
        {\qfdRelTitle};
      \draw[qfdthin] (0, -0.15) -- (4.35, -0.15);
      \node[qfdstrong] at (0.22, -0.5)  {};
        \node[anchor=west] at (0.5, -0.5)  {Strong (9)};
      \node[qfdmod]    at (0.22, -0.95) {};
        \node[anchor=west] at (0.5, -0.95) {Medium (3)};
      \node[qfdweak]   at (0.22, -1.4)  {};
        \node[anchor=west] at (0.5, -1.4)  {Weak (1)};
      % Correlations (roof)
      \ifqfdshowroof \ifqfdshowcorrlegend
        \node[anchor=west, font=\footnotesize\bfseries] at (0, -2.10)
          {\qfdCorrTitle};
        \draw[qfdthin] (0, -2.35) -- (4.35, -2.35);
        \node[anchor=west] at (0, -2.70) {{$+\!+$}\quad very positive};
        \node[anchor=west] at (0, -3.05) {{$+$\phantom{$+$}}\quad positive};
        \node[anchor=west] at (0, -3.40) {{$-$\phantom{$-$}}\quad negative};
        \node[anchor=west] at (0, -3.75) {{$-\!-$}\quad very negative};
      \fi \fi
      % Evaluation (3 alternatives)
      \ifqfdshowcompetitive \ifqfdshowevallegend
        \pgfmathsetmacro{\qfdEvalTop}{%
          -2.10 \ifqfdshowroof\ifqfdshowcorrlegend - 2.55 \fi\fi}
        \node[anchor=west, font=\footnotesize\bfseries]
          at (0, \qfdEvalTop) {\qfdEvalTitle};
        \pgfmathsetmacro{\qfdEvalSep}{\qfdEvalTop - 0.25}
        \draw[qfdthin] (0, \qfdEvalSep) -- (4.35, \qfdEvalSep);
        \pgfmathsetmacro{\qfdLegA}{\qfdEvalTop - 0.55}
        \draw[qfdalt1ln] (0.05, \qfdLegA) -- (0.45, \qfdLegA);
          \node[qfdalt1mk] at (0.25, \qfdLegA) {};
          \node[anchor=west, font=\bfseries] at (0.55, \qfdLegA)
            {\qfdAltOneLabel};
        \pgfmathsetmacro{\qfdLegB}{\qfdEvalTop - 0.95}
        \draw[qfdalt2ln] (0.05, \qfdLegB) -- (0.45, \qfdLegB);
          \node[qfdalt2mk] at (0.25, \qfdLegB) {};
          \node[anchor=west] at (0.55, \qfdLegB) {\qfdAltTwoLabel};
        \pgfmathsetmacro{\qfdLegC}{\qfdEvalTop - 1.35}
        \draw[qfdalt3ln] (0.05, \qfdLegC) -- (0.45, \qfdLegC);
          \node[qfdalt3mk] at (0.25, \qfdLegC) {};
          \node[anchor=west] at (0.55, \qfdLegC) {\qfdAltThreeLabel};
      \fi \fi
    \end{scope}
  \fi
}

% --- The environment users wrap their content in. ---
\newenvironment{qfdhouse}{%
  \begin{tikzpicture}[x=1cm, y=1cm, font=\scriptsize,
                      line cap=round, line join=round]
  \ifqfdshowimportance
    \pgfmathsetmacro{\qfdLeftEdge}{-\qfdWhatW-\qfdImpW}
  \else
    \pgfmathsetmacro{\qfdLeftEdge}{-\qfdWhatW}
  \fi
  \pgfmathsetmacro{\qfdApexY}{\qfdHdrH + \qfdNH/2}
  \pgfmathtruncatemacro{\qfdNHm}{\qfdNH - 1}
  \pgfmathtruncatemacro{\qfdNWm}{\qfdNW - 1}
  \qfdDrawGrid
  \qfdDrawRoof
  \qfdDrawScale
  \qfdDrawZoneTitles
  \qfdDrawTitle
}{%
  \qfdDrawFrames
  \qfdDrawLegend
  \end{tikzpicture}%
}

\def\qfdNW{10}
\def\qfdNH{11}
\def\qfdWhatW{4.6}
\def\qfdImpW{0.9}
\def\qfdHdrH{3.6}
\def\qfdWhatsTitle{Goals (TPS house)}
\qfdshowcompetitivefalse
\def\qfdProjectTitle{Pull Kanban --- bluebin.app}
\def\qfdConcept{A \textbf{pull} system where \textbf{Kanbans} start \textbf{Work Stations}, \textbf{Heijunka} levels the \textbf{Demands}, and each \textbf{Piece} reaches the \textbf{Client} at \textbf{Takt Time}.}

\begin{document}
\hyphenpenalty=10000 \exhyphenpenalty=10000
\begin{qfdhouse}
  % WHATs
  \pgfmathsetmacro{\qfdWhatTextW}{\qfdWhatW - 0.2}
  \foreach \r/\t in {1/{G1 Client: Takt Time visible to all},
                     2/{G2 Pull, every Deviation visible},
                     3/{G3 One-piece flow at Takt Time},
                     4/{G4 Jidoka: stop and fix},
                     5/{G5 Person knows the next thing},
                     6/{G6 Levelled Product Mix},
                     7/{G7 Value Stream at a glance},
                     8/{G8 Recording costs seconds},
                     9/{G9 Flow problems as numbers},
                     10/{G10 Design and change without code}}
    \node[anchor=west, font=\scriptsize, text width=\qfdWhatTextW cm, align=left]
      at ({\qfdLeftEdge + 0.1}, {-\r + 0.5}) {\t};
  % Importance (%)
  \foreach \r/\imp in {1/12, 2/11, 3/10, 4/10, 5/11, 6/9, 7/10, 8/10, 9/10, 10/7}
    \node[font=\scriptsize] at ({-\qfdImpW/2}, {-\r + 0.5}) {\imp};
  % HOWs
  \foreach \c/\t in {1/{F2 Takt Gap updated},
                     2/{F3 Takt Andon},
                     3/{F6 Deviation warning},
                     4/{F7 Kanban on each pull},
                     5/{F13 Rework to its author},
                     6/{F17 Assignments updated},
                     7/{F23 Heijunka Sequence},
                     8/{F28 Live screens},
                     9/{F30 Record a flow event},
                     10/{F34 Exact measures},
                     11/{F40 Change while running}}
    \node[rotate=90, anchor=west, font=\scriptsize] at ({\c - 0.5}, 0.15) {\t};
  % Relations: column/row/strength
  \foreach \c/\r/\s in {1/1/S, 2/1/S, 7/1/M, 8/1/M, 9/1/M, 10/1/M,
                        3/2/S, 4/2/S, 6/2/M,
                        1/3/M, 4/3/M, 7/3/M, 10/3/M, 6/3/W,
                        5/4/S, 2/4/M, 6/4/M,
                        6/5/S, 5/5/M, 4/5/M, 8/5/M,
                        7/6/S, 4/6/M,
                        8/7/S, 2/7/M, 3/7/M, 4/7/M,
                        9/8/S, 3/8/W, 6/8/W,
                        10/9/S, 9/9/M, 11/9/M,
                        11/10/S, 10/10/W}
    \node[qfdrel/\s] at ({\c - 0.5}, {-\r + 0.5}) {};
  % Roof correlations
  \node[font=\scriptsize] at (C-1-2)  {$+\!+$};
  \node[font=\scriptsize] at (C-9-10) {$+\!+$};
  \node[font=\scriptsize] at (C-6-8)  {$+\!+$};
  \node[font=\scriptsize] at (C-4-6)  {$+$};
  \node[font=\scriptsize] at (C-1-8)  {$-$};
  \node[font=\scriptsize] at (C-2-6)  {$-$};
  \node[font=\scriptsize] at (C-3-9)  {$-$};
  \node[font=\scriptsize] at (C-10-11) {$-\!-$};
  % Basement: target / difficulty / absolute / relative
  \foreach \c/\tgt/\diff/\abs/\rel in
    {1/{$\leq$1\,min}/2/138/8,
     2/{$\leq$1\,min}/2/168/10,
     3/{100\,\%}/2/139/8,
     4/{$\leq$\,bins}/3/219/13,
     5/{$\leq$1\,min}/2/123/7,
     6/{$\leq$2\,s}/3/182/11,
     7/{$\leq$1\,min}/3/147/9,
     8/{$\leq$2\,s}/3/159/9,
     9/{$\leq$5\,s}/4/156/9,
     10/{exact}/4/163/10,
     11/{0 lost}/5/93/6} {
    \node[font=\tiny] at ({\c - 0.5}, {-\qfdNW - 0.5}) {\tgt};
    \node[font=\scriptsize] at ({\c - 0.5}, {-\qfdNW - 1.5}) {\diff};
    \node[font=\scriptsize] at ({\c - 0.5}, {-\qfdNW - 2.5}) {\abs};
    \node[font=\scriptsize\bfseries] at ({\c - 0.5}, {-\qfdNW - 3.5}) {\rel};
  }
  \foreach \r/\t in {1/Target, 2/Difficulty (1--5), 3/Absolute weight, 4/Relative weight \%}
    \node[anchor=east, font=\scriptsize\itshape] at (-0.1, {-\qfdNW - \r + 0.5}) {\t};
\end{qfdhouse}
\end{document}
```

---

## 1. Goals — the WHATs

User-facing outcomes, weight 1–10, grouped by the parts of the Toyota Production System house: the roof is the goal, two pillars hold it, People work in the centre, and the foundation carries everything.

```tikz
\usetikzlibrary{positioning, calc}
\begin{document}
\hyphenpenalty=10000 \exhyphenpenalty=10000
\begin{tikzpicture}[x=1cm, y=1cm, line join=round,
  box/.style={draw, line width=0.8pt},
  head/.style={font=\bfseries\small, align=center},
  body/.style={font=\scriptsize, align=center, text width=#1 cm},
  ids/.style={font=\scriptsize\itshape, align=center}]
  % Title
  \node[font=\large\bfseries] at (7, 14.3) {Pull Kanban --- the TPS house};
  % Roof
  \draw[box, fill=black!8] (-0.8, 9) -- (7, 13.4) -- (14.8, 9) -- cycle;
  \node[head] at (7, 11.25) {Roof --- Client satisfaction};
  \node[body=7.5] at (7, 10.35) {G1 Everyone is aligned on the active \textbf{Demands} and sees whether each one is on its \textbf{Takt Time} for its \textbf{Client}};
  \node[ids] at (7, 9.35) {F1--F5 \quad Takt Gap, Andon, forecast, on-time share};
  % Pillars
  \draw[box] (0, 3) rectangle (4, 9);
  \node[head] at (2, 8.4) {Just-In-Time};
  \node[body=3.6] at (2, 6.9) {G2 Starting work without a \textbf{Kanban} is never silent: each \textbf{Deviation} is visible};
  \node[body=3.6] at (2, 5.2) {G3 Each \textbf{Piece} flows alone at its \textbf{Demand}'s \textbf{Takt Time}};
  \node[ids] at (2, 3.5) {F6--F11};
  \draw[box] (10, 3) rectangle (14, 9);
  \node[head] at (12, 8.4) {Jidoka};
  \node[body=3.6] at (12, 6.6) {G4 A defect stops the flow where it is found, and its author repairs it first (\textbf{Rework})};
  \node[body=3.6] at (12, 4.8) {\textbf{Andon} button: stop the \textbf{Work Station}, call the \textbf{Team Leader}};
  \node[ids] at (12, 3.5) {F12--F16, F42};
  % Centre
  \draw[box, rounded corners=4pt, fill=black!4] (4.6, 3.6) rectangle (9.4, 8.4);
  \node[head] at (7, 7.8) {People and teamwork};
  \node[body=4.4] at (7, 6.3) {G5 A \textbf{Person} always knows the next thing to do: an \textbf{Assignment}, a \textbf{Rework}, \textbf{Help Downstream}, or wait};
  \node[ids] at (7, 4.2) {F17--F22};
  % Foundation
  \draw[box] (-0.8, 2) rectangle (14.8, 3);
  \node[head, anchor=west] at (-0.6, 2.5) {Heijunka};
  \node[body=8.5, anchor=west, align=left] at (3.2, 2.5) {G6 The \textbf{Pieces} that leave the \textbf{Backlog} have a levelled \textbf{Product Mix}};
  \node[ids, anchor=east] at (14.6, 2.5) {F23--F26};
  \draw[box] (-0.8, 1) rectangle (14.8, 2);
  \node[head, anchor=west, align=left] at (-0.6, 1.5) {Stability and\\visual management};
  \node[body=8.5, anchor=west, align=left] at (3.2, 1.5) {G7 The \textbf{Value Stream} is visible at a glance \quad G8 Recording work costs seconds};
  \node[ids, anchor=east] at (14.6, 1.5) {F27--F33};
  \draw[box] (-0.8, 0) rectangle (14.8, 1);
  \node[head, anchor=west] at (-0.6, 0.5) {Kaizen};
  \node[body=8.5, anchor=west, align=left] at (3.2, 0.5) {G9 Flow problems show as numbers \quad G10 Design and change the \textbf{Value Stream} without code};
  \node[ids, anchor=east] at (14.6, 0.5) {F34--F41};
  % Deferred
  \draw[line width=0.6pt, dashed, black!55] (-0.8, -0.25) rectangle (14.8, -1.05);
  \node[font=\scriptsize\itshape, black!65] at (7, -0.65) {Standardized Work --- deferred (Definition of Done per \textbf{Work Station})};
\end{tikzpicture}
\end{document}
```

| ID | Goal | Weight | Source |
|----|------|:------:|--------|
| **Roof — Client satisfaction** | | | |
| G1 | Everyone is aligned on the active **Demands** and sees, at all times, whether each one is on its **Takt Time** for its **Client** | 10 | Session decision (2026-11-03) |
| **Pillar — Just-In-Time** | | | |
| G2 | Starting work without a **Kanban** is never silent: each **Deviation** is visible and has a reason | 9 | Kick-off conversation (2026-11-03) |
| G3 | Each **Piece** flows alone and reaches production at its **Demand**'s **Takt Time** | 8 | Kick-off conversation |
| **Pillar — Jidoka** | | | |
| G4 | A defect stops the flow where it is found, and its author repairs it first (**Rework**) | 8 | Session decision (2026-11-03) |
| **Centre — People and teamwork** | | | |
| G5 | A **Person** always knows the next thing to do: an **Assignment**, a **Rework**, **Help Downstream**, or wait | 9 | Kick-off conversation |
| **Foundation — Heijunka** | | | |
| G6 | The **Pieces** that leave the **Backlog** have a levelled **Product Mix** | 7 | Kick-off conversation |
| **Foundation — Stability and visual management** | | | |
| G7 | The whole **Value Stream** is visible at a glance: **Kanbans**, **Blue Bins**, **Rework**, bottleneck | 8 | Kick-off conversation |
| G8 | Recording work costs seconds, so the data stays true | 8 | Kick-off conversation |
| **Foundation — Kaizen** | | | |
| G9 | Flow problems show as numbers: **Lead Time**, **Stagnation Time**, **Starvation Time**, **Rework Time** | 8 | Kick-off conversation |
| G10 | A **Value Stream** can be designed and changed without code: **Work Stations**, **Branches**, **Blue Bins**, **People**, **Working Calendar** | 6 | Kick-off conversation |

User segments: **Person** (daily work), Value Stream designer (design and Kaizen), **Client** and Demand owner (Demands and **Takt Time**).

Deferred: **Standardized Work** (foundation). The Definition of Done of each **Work Station** stays out of the app for now. **Trigger to revisit:** **Rework** shows that **Work Stations** disagree on what "done" means.

---

## 2. Functions — the HOWs

Measurable responsibilities. Direction: ↑ higher is better, ↓ lower is better, → fixed value.

| ID | Function | Dir | Target | Goal |
|----|----------|:---:|--------|------|
| **Roof — Client satisfaction** | | | | |
| F1 | Show every active **Demand** with its **Client**, due date, **Takt Time** and **Takt Gap**, in one view that is the same for everyone | → | 1 shared view, open in ≤ 1 s | G1 |
| F2 | Update the **Takt Gap** when a **Piece** reaches production, and as **Working Time** passes | ↓ | ≤ 1 min after the event | G1 |
| F3 | Raise an **Andon** to all **People** when a **Demand** falls behind its **Takt Time** (**Takt Gap** ≤ −1) | ↓ | ≤ 1 min | G1 |
| F4 | Forecast the delivery date of each **Demand** from its current flow, and compare it with the due date | ↓ | error ≤ 1 working day | G1 |
| F5 | Measure the share of **Demands** that reach production by their due date | ↑ | ≥ 90 % | G1 |
| **Pillar — Just-In-Time** | | | | |
| F6 | Warn before a pull without a **Kanban**, and record a **Deviation** with its reason if the **Person** goes on | → | 100 % warned and recorded | G2 |
| F7 | Send one **Kanban** upstream for each pull out of a **Blue Bin**, and one **Kanban** to each **Branch** for each **Assembly** | → | **Kanbans** ≤ empty **Blue Bins**, at all times | G2 |
| F8 | Warn before an **Assembly** when a **Sub-Piece** is not in the last **Blue Bin** of its **Branch**, and record a **Deviation** with its reason if the **Person** goes on | → | 100 % warned and recorded | G2 |
| F9 | Warn before a second **Piece** goes in a **Blue Bin**, and record a **Deviation** with its reason if the **Person** goes on | → | 100 % warned and recorded | G3 |
| F10 | Compare the capacity of each **Work Station** (average **Touch Time** ÷ **People** working) with the **Takt Time** of the **Value Stream**, and flag the slower ones | ↓ | flag ≤ 1 working day after the change | G3 |
| F11 | Recompute the **Takt Time** of the **Value Stream** when a **Demand** enters or ends | ↓ | ≤ 1 min | G3 |
| **Pillar — Jidoka** | | | | |
| F12 | Raise **Rework** on a **Piece**: name the **Work Station** that made the defect, and describe the defect in one line | ↓ | ≤ 2 clicks, ≤ 10 s | G4 |
| F13 | Give the **Rework** to its author by default: put it first in their **Assignments** and pause their current **Piece** | ↓ | ≤ 1 min after the **Rework** is raised | G4 |
| F14 | Warn before the downstream **Work Station** pulls a new **Piece** while its **Rework** is open, and record a **Deviation** if it goes on | → | 100 % warned and recorded | G4 |
| F15 | Raise an **Andon** when a **Rework** waits without an active **Assignment** | ↓ | after ≤ 1 h of **Working Time** | G4 |
| F16 | Measure, for each **Work Station**, its **Rework Time** and its **First Pass Yield** | ↑ | **First Pass Yield** ≥ 90 % | G4 |
| F42 | Let any **Person** raise an **Andon** on their **Work Station** with one button: it stops the **Work Station** and calls its **Team Leader**, who closes it | ↓ | 1 click; **Team Leader** called ≤ 1 min | G4 |
| **Centre — People and teamwork** | | | | |
| F17 | Update the **Priority List** of each **Work Station** and the **Assignments** of each **Person** after any flow event | ↓ | ≤ 2 s | G5 |
| F18 | Order **Priority Lists** and **Assignments** by the glossary rules: **Rework**, then nearest to production, then oldest | → | 100 % of cases | G5 |
| F19 | Show each **Person** one next thing: their active **Assignment**, the top **Kanban** they can take, a **Help Downstream** target, or "wait" | ↓ | 1 screen, ≤ 1 s | G5 |
| F20 | Let a free **Person** take the top **Kanban** of their **Work Station** nearest to production | ↓ | 1 click | G5 |
| F21 | Let any **Person** of a **Work Station** reassign an **Assignment** to another **Person** of the same **Work Station** | ↓ | ≤ 2 clicks | G5 |
| F22 | Propose a **Help Downstream** target: the nearest downstream **Work Station** that holds up the flow (open **Rework**, or a full **Blue Bin** in front of it) | → | always shown when the **Person** has no **Kanban** | G5 |
| **Foundation — Heijunka** | | | | |
| F23 | Compute the **Heijunka Sequence** from the **Takt Time** of each active **Demand**: earliest slot, then earliest due date, then first-in, first-out | ↓ | recomputed ≤ 1 min after a **Demand** enters, ends or changes | G6 |
| F24 | Release the top **Piece** of the **Backlog** only when the first **Work Station** takes a **Kanban** | → | 100 % of releases | G6 |
| F25 | Let a **Person** reorder the **Heijunka Sequence** by hand as a **Deviation** with its reason, and show the effect on the **Takt Gap** and the forecast of each **Demand** before they confirm | ↓ | effect shown ≤ 2 s | G6 |
| F26 | Measure, for each day, the gap between the planned and the real **Product Mix** of the **Pieces** that leave the **Backlog** | ↓ | ≤ 1 **Piece** for each **Demand**, each day | G6 |
| **Foundation — Stability and visual management** | | | | |
| F27 | Show the **Value Stream** view: each **Work Station** with its **Blue Bins** (full or empty), **Kanbans**, **People**, active **Assignments**, open **Rework**, **Deviations** and **Andons** | ↓ | 1 screen, readable on a wall TV | G7 |
| F28 | Update every open view after a flow event, with no manual refresh | ↓ | ≤ 2 s | G7 |
| F29 | Highlight the bottleneck: the **Work Stations** flagged by F10, or with a full **Blue Bin** in front of them | ↓ | ≤ 1 min after the change | G7 |
| F30 | Record a flow event (pull, put in **Blue Bin**, **Assembly**, take a **Kanban**, reassign) | ↓ | ≤ 2 clicks, ≤ 5 s | G8 |
| F31 | Record a **Deviation** reason in one line | ↓ | ≤ 10 s | G8 |
| F32 | Pause the current **Piece** automatically when a **Person** takes another **Assignment** | → | 100 %, with no manual step | G8 |
| F33 | Show stale **Assignments**: active, with no event for more than 1 working day | ↓ | ≤ 5 % of active **Assignments** | G8 |
| **Foundation — Kaizen** | | | | |
| F34 | Compute **Lead Time**, **Station Lead Time**, **Touch Time** and **Stagnation Time** for each **Piece** and each **Demand**, and **Starvation Time** for each **Work Station**, from the flow events | → | **Lead Time** = **Touch Time** + **Stagnation Time**, exactly | G9 |
| F35 | Switch every measure between **Calendar Time** (the default) and **Working Time** | ↓ | 1 click | G9 |
| F36 | Show, for each **Work Station**, the share of **Touch Time** in the **Station Lead Time** | ↑ | value visible for each **Work Station** | G9 |
| F37 | Show the **Deviations** for each **Work Station** and for each rule, with their reasons | ↓ | ≤ 5 % of pulls | G9 |
| F38 | Compare two periods (before and after a **Value Stream** change) on all measures | ↓ | 1 view | G9 |
| F39 | Design a **Value Stream**: **Work Stations**, **Splits**, **Branches**, **Assembly**, **Blue Bin** count, **People**, **Working Calendar** | ↓ | the software team example in ≤ 30 min | G10 |
| F40 | Change a **Value Stream** while it runs (**Blue Bins**, **People**, **Work Stations**), keep all past events, and date each change | → | 0 lost events, 100 % of changes dated | G10 |
| F41 | Let each **Value Stream** name its own **Demands** and **Pieces**, for example "Feature" and "User Story" | → | free labels for each **Value Stream** | G10 |

---

## 4. Cascade — Goals → Functions → How → Components

- **G1** Client satisfaction, Takt Time visible to everyone  _W:10_ — F1–F5
- **G2** Pull, every **Deviation** visible  _W:9_ — F6–F9
- **G3** One-piece flow at **Takt Time**  _W:8_ — F10–F11
- **G4** Jidoka, stop and fix  _W:8_ — F12–F16, F42
- **G5** A **Person** knows the next thing to do  _W:9_ — F17–F22
- **G6** Levelled **Product Mix**  _W:7_ — F23–F26
- **G7** **Value Stream** at a glance  _W:8_ — F27–F29
- **G8** Recording costs seconds  _W:8_ — F30–F33
- **G9** Flow problems as numbers  _W:8_ — F34–F38
- **G10** Design and change without code  _W:6_ — F39–F41

Core How decisions, shared by many Functions:

- **How H3 — flow events + current state, in one transaction** (chosen, see T1)
  - Serves: F2, F34, F35, F38, F40 (history and measures), F17, F27 (fast reads)
  - Each action appends one flow event to an append-only log, and updates the current-state tables in the same transaction
  - Every measure can be recomputed from the log, for example after a **Working Calendar** change
- **How H1 — current state only** (rejected, see T1)
- **How H2 — full event sourcing** (rejected, see T1)
- **How H5 — Server-Sent Events** (chosen, see T2)
  - Serves: F2, F3, F15, F17, F27, F28 (every open screen updated in ≤ 2 s)
  - Each new flow event in the log is pushed to the open screens of its **Value Stream**; actions still go as normal HTTP requests
  - A screen that reconnects reloads the current state; nothing is lost, because the log is the source of truth
- **How H4 — polling every 2 s** (rejected, see T2)
- **How H6 — WebSockets** (rejected, see T2)

Components that realise these How decisions:

- **C1** SPA — Vite + Vue 3 + TypeScript + Tailwind v4 + DaisyUI
- **C2** API — Gleam (wisp + mist): flow rules, **Deviations**, **Priority List** ordering, Heijunka sequencer
- **C3** Store — SQLite (sqlight): flow event log + current-state tables (H3)
- **C4** Event stream — Server-Sent Events from mist (H5)
- **C5** Deploy — Coolify, docker compose (web + API), on bluebin.app

---

## 5. House — Goals × key Functions

Reduced to the 11 Functions that serve several Goals; the other Functions map to one Goal each (see §4). Importance = Goal weight as a share of the total (81). Cells: 9 strong, 3 medium, 1 weak.

|            | F2 | F3 | F6 | F7 | F13 | F17 | F23 | F28 | F30 | F34 | F40 |
|------------|:--:|:--:|:--:|:--:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| G1 (12 %)  | 9  | 9  |    |    |     |     |  3  |  3  |  3  |  3  |     |
| G2 (11 %)  |    |    | 9  | 9  |     |  3  |     |     |     |     |     |
| G3 (10 %)  | 3  |    |    | 3  |     |  1  |  3  |     |     |  3  |     |
| G4 (10 %)  |    | 3  |    |    |  9  |  3  |     |     |     |     |     |
| G5 (11 %)  |    |    |    | 3  |  3  |  9  |     |  3  |     |     |     |
| G6 (9 %)   |    |    |    | 3  |     |     |  9  |     |     |     |     |
| G7 (10 %)  |    | 3  | 3  | 3  |     |     |     |  9  |     |     |     |
| G8 (10 %)  |    |    | 1  |    |     |  1  |     |     |  9  |     |     |
| G9 (10 %)  |    |    |    |    |     |     |     |     |  3  |  9  |  3  |
| G10 (7 %)  |    |    |    |    |     |     |     |     |     |  1  |  9  |
| **Σ**      | 138 | 168 | 139 | 219 | 123 | 182 | 147 | 159 | 156 | 163 | 93 |
| **Rank**   | 9  | 3  | 8  | 1  | 10  | 2   | 7   | 5   | 6   | 4   | 11  |

**Top engineering priorities:** F7 (a **Kanban** on each pull) and F17 (**Assignments** updated) carry the pull system and the daily work of every **Person**; F3 (**Andon**) and F34 (exact measures) carry the roof and Kaizen. F40 ranks last but is the hardest (R1), so it gets the simplest rule: only empty **Blue Bins** and **Work Stations** can be removed.

---

## 6. Roof — Function × Function conflicts

Symbols: `⊗` strong conflict, `×` mild conflict.

| ID | Conflict | Strength | Mitigation |
|----|----------|:--------:|------------|
| R1 | F40 change while running vs F34 exact measures | ⊗ | A change can remove only an empty **Blue Bin**, or a **Work Station** with no **Piece**; measures split at the date of the change |
| R2 | F3, F15, F42 **Andons** vs F19 one next thing | × | **Andons** show on the wall TV and the **Demand** view; on a **Person**'s screen, only their own **Rework** and their **Work Station**'s **Andons** interrupt them |
| R3 | **Deviation** reasons (F6, F8, F9, F14, F25) vs F30 recording costs seconds | × | One-line reason, past reasons suggested, ≤ 10 s (F31) |
| R4 | F25 manual reorder vs F26 levelled **Product Mix** | ⊗ | Accepted by design: each reorder is a **Deviation**, its cost is shown before confirmation, F26 shows the drift |
| R5 | F13 **Rework** pauses its author vs F10 flow at **Takt Time** upstream | × | Accepted: fix first; the pause shows as **Stagnation Time** |
| R6 | F2 **Takt Gap** "as **Working Time** passes" vs H5 push on events | × | The API emits a timer event every minute of **Working Time**; SSE pushes it like a flow event |

---

## 7. Components

| ID | Component | Role | Main Functions | ADR |
|----|-----------|------|----------------|-----|
| C1 | SPA: Vite + Vue 3 + TypeScript + Tailwind v4 + DaisyUI | All screens: **Demands** and **Takt Gap**, **Assignments**, **Value Stream** view (wall TV), **Value Stream** designer, measures | F1, F19, F25, F27, F35, F38, F39 | — |
| C2 | API: Gleam (wisp + mist) | HTTP actions; pull rules and **Deviations**; **Priority List** and **Assignment** ordering; Heijunka sequencer; measures | F6–F26, F30–F34, F40 | — |
| C3 | Store: SQLite (sqlight) | Flow event log and current-state tables, written in one transaction | F34, F38, F40 | [ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md) |
| C4 | Event stream: Server-Sent Events from mist | Pushes each new flow event to the open screens | F2, F3, F15, F17, F28 | — |
| C5 | Deploy: Coolify, docker compose (web + API), bluebin.app | Hosting | — | — |

---

## 8. Critical performance budget

| Rank | Function | Target | Watched on | If we miss it |
|:----:|----------|--------|------------|---------------|
| 1 | F30 record a flow event | ≤ 2 clicks, ≤ 5 s | Time from opening the screen to confirming the action, measured in the SPA | Quick-action button on each **Assignment**, plus keyboard shortcuts; if events are still skipped, F33 shows the gaps and the **Team Leader** fixes them |
| 2 | F17 / F28 **Assignments** and screens updated | ≤ 2 s | Time from writing the event to the screen update, logged by the API and the SPA | The SPA reloads the current state when SSE is late (H4 polling as fallback) |
| 3 | F34 **Lead Time** = **Touch Time** + **Stagnation Time** | exact | Nightly job that recomputes the measures from the log and compares | The log is the truth: rebuild the current-state tables from it ([ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md)) |
| 4 | F2 / F3 **Takt Gap** and **Andon** | ≤ 1 min | Time from the timer tick or event to the **Andon** on screen | The **Takt Gap** is also computed when a screen opens, so a missed tick does no harm |
| 5 | F4 delivery forecast | error ≤ 1 working day | Forecast date vs real date, for each finished **Demand** | Show a date range, not one date, until the error goes down |
| 6 | F39 design the software team's **Value Stream** | ≤ 30 min | Time measured in the first real session with the team | Supply a "software team" template, with the **Split** for Web, iOS and Android |

---

## 9. Tradeoffs — Got / Paid / ADR

| ID | Tradeoff | Got | Paid | ADR |
|----|----------|-----|------|-----|
| T1 | Flow events + current state in one transaction (H3), over current state only (H1) and full event sourcing (H2) | Full history; every measure can be recomputed; dated **Value Stream** changes; simple, fast reads for daily screens | Two writes for each action that must stay consistent; the log grows forever | [ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md) |
| T2 | Server-Sent Events (H5), over polling (H4) and WebSockets (H6) | Updates in less than 1 s; standard browser reconnect; one direction is all we need | One open connection for each screen; actions and updates use two channels | — |
| T3 | SQLite (C3), over Postgres | One file, real transactions, no database server; fits the one-writer flow of a team | Single writer: a move to Postgres when many teams share one instance (H3 does not change) | — |

### Tensions being watched (unresolved by design)

- **Single SQLite writer.** One instance serves one or a few teams. **Trigger to revisit:** many teams share one instance, or write latency breaks F17.
- **Standardized Work out of the app.** No Definition of Done per **Work Station**. **Trigger to revisit:** **Rework** shows that **Work Stations** disagree on what "done" means.
- **Acceptance of a whole Feature.** Each **Piece** goes to production alone; there is no **Demand**-level acceptance. **Trigger to revisit:** a **Client** cannot accept value one **Piece** at a time.
- **No personal notifications.** Only **Andons** interrupt. **Trigger to revisit:** stale **Assignments** (F33) stay above 5 %.

---

## 10. Inconsistencies spotted and fixed

- **Soft pull rules vs "never" in the glossary and in G2.** F6, F8 and F9 warn and do not block, but [CONTEXT.md](./CONTEXT.md) said a **Person** never starts work without a **Kanban**, and G2 said overproduction is impossible. Resolved: new term **Deviation** (a broken rule, with a required reason, visible at once); the glossary now says "only as a **Deviation**"; G2 now says "never silent".
- **Help Downstream target.** During the glossary session, Help Downstream was said to point at the **Work Station** with the most **Starvation Time**. A starved **Work Station** is downstream of the problem, not the problem. Resolved: F22 points at the nearest downstream **Work Station** that holds up the flow, which matches the **Help Downstream** definition.
- **F9 and the automatic pause.** F9 also warned before a second active **Assignment**, but taking an **Assignment** pauses the current one automatically, so a second active one cannot happen. Resolved: F9 covers only the second **Piece** in a **Blue Bin**.

---

## How to keep this honest

- When a new ADR lands, add its components to the component map and re-score the affected rows.
- When a measurement returns numbers, update the targets and the performance budget.
- Goals change rarely; functions change with each release; matrices are recomputed when either side changes.
- If a section becomes empty after edits, delete it.
