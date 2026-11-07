# Bluebin — Design (QFD)

This document designs Bluebin: how a team designs its Line and then runs its daily work in it, with pull, Takt Time and Heijunka. It does not define terms: every term in **bold** is defined in [CONTEXT.md](./CONTEXT.md). Decisions that are hard to reverse go in [docs/adr/](./docs/adr/).

Strength weights used in matrices: **9** strong, **3** medium, **1** weak, blank none.

---

## House of Quality

The at-a-glance view of the design: the 10 Goals (§1) against 11 key Functions (§2) chosen for their cross-cutting weight, with the roof conflicts (§6), the derived weights (§5) and, on the right, how Bluebin is meant to score against the three alternatives a team already has (Jira, Linear, a physical board). Row colours match the parts of the TPS house in §1; the blue boxes mark the 3 Functions with the highest weight. In the comparative evaluation, each alternative has its own colour: Bluebin blue, Jira orange, Linear purple, physical board brown. Red and green are kept for OK / NOK status only, so neither house uses them.

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
\newif\ifqfdshowaltfour       \qfdshowaltfourfalse % 4th alternative in the perception zone
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
\def\qfdAltFourLabel{Competitor C}  % shown only with \qfdshowaltfourtrue
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
  qfdalt4mk/.style={diamond, draw, fill=black,
                    minimum size=6pt, inner sep=0pt, line width=0.7pt},
  qfdalt4ln/.style={line width=0.7pt,
                    dash pattern=on 3pt off 1.5pt on 0.8pt off 1.5pt},
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
      \ifqfdshowcompetitive \ifqfdshowevallegend - 2.20
        \ifqfdshowaltfour - 0.40 \fi \fi \fi}
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
        \ifqfdshowaltfour
          \pgfmathsetmacro{\qfdLegD}{\qfdEvalTop - 1.75}
          \draw[qfdalt4ln] (0.05, \qfdLegD) -- (0.45, \qfdLegD);
            \node[qfdalt4mk] at (0.25, \qfdLegD) {};
            \node[anchor=west] at (0.55, \qfdLegD) {\qfdAltFourLabel};
        \fi
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

\definecolor{bbRoof}{HTML}{B7791F}
\definecolor{bbJit}{HTML}{2B6CB0}
\definecolor{bbJidoka}{HTML}{6B46C1}
\definecolor{bbPeople}{HTML}{B83280}
\definecolor{bbBase}{HTML}{4A5568}
% Comparative evaluation: one colour per alternative (no red, no green)
\definecolor{bbAltBluebin}{HTML}{2B6CB0}
\definecolor{bbAltJira}{HTML}{DD6B20}
\definecolor{bbAltLinear}{HTML}{805AD5}
\definecolor{bbAltBoard}{HTML}{8C5A2B}
\tikzset{
  qfdalt1mk/.append style={draw=bbAltBluebin, fill=bbAltBluebin},
  qfdalt1ln/.append style={draw=bbAltBluebin},
  qfdalt2mk/.append style={draw=bbAltJira, fill=bbAltJira},
  qfdalt2ln/.append style={draw=bbAltJira},
  qfdalt3mk/.append style={draw=bbAltLinear, fill=bbAltLinear},
  qfdalt3ln/.append style={draw=bbAltLinear},
  qfdalt4mk/.append style={draw=bbAltBoard, fill=bbAltBoard},
  qfdalt4ln/.append style={draw=bbAltBoard},
}
\def\qfdNW{10}
\def\qfdNH{11}
\def\qfdWhatW{4.6}
\def\qfdImpW{0.9}
\def\qfdHdrH{3.6}
\def\qfdWhatsTitle{Goals (TPS house)}
\def\qfdCmpW{3.8}
\qfdshowaltfourtrue
\def\qfdAltOneLabel{Bluebin (target)}
\def\qfdAltTwoLabel{Jira}
\def\qfdAltThreeLabel{Linear}
\def\qfdAltFourLabel{Physical board + cards}
% Coordinate of score #2 (0--5) on the row of Goal #1.
\newcommand{\bbEv}[2]{({\qfdNH + (#2+0.5)*\qfdCmpW/6}, {-#1 + 0.5})}
\def\qfdProjectTitle{Bluebin}
\def\qfdConcept{A \textbf{pull} system where \textbf{Kanbans} start \textbf{Work Stations}, \textbf{Heijunka} levels the \textbf{Demands}, and each \textbf{Piece} reaches the \textbf{Client} at \textbf{Takt Time}.}

\begin{document}
\hyphenpenalty=10000 \exhyphenpenalty=10000
\begin{qfdhouse}
  % Goal rows coloured by their part of the TPS house
  \begin{scope}[on background layer]
    \foreach \r/\col in {1/bbRoof, 2/bbJit, 3/bbJit, 4/bbJidoka, 5/bbPeople,
                         6/bbBase, 7/bbBase, 8/bbBase, 9/bbBase, 10/bbBase} {
      \fill[\col!14] (\qfdLeftEdge, -\r + 1) rectangle (-\qfdImpW, -\r);
      \fill[\col] (\qfdLeftEdge, -\r + 1) rectangle ({\qfdLeftEdge + 0.12}, -\r);
    }
  \end{scope}
  % WHATs
  \pgfmathsetmacro{\qfdWhatTextW}{\qfdWhatW - 0.3}
  \foreach \r/\t in {1/{G1 Client: Takt Time visible to all},
                     2/{G2 Pull, every Deviation visible},
                     3/{G3 One-piece flow at Takt Time},
                     4/{G4 Jidoka: stop and fix},
                     5/{G5 Team Member knows the next thing},
                     6/{G6 Levelled Product Mix},
                     7/{G7 Line at a glance},
                     8/{G8 Recording costs seconds},
                     9/{G9 Flow problems as numbers},
                     10/{G10 Design and change without code}}
    \node[anchor=west, font=\scriptsize, text width=\qfdWhatTextW cm, align=left]
      at ({\qfdLeftEdge + 0.18}, {-\r + 0.5}) {\t};
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
  % Top 3 Functions by weight (F7, F17, F3)
  \foreach \c in {4, 6, 2}
    \draw[bbJit, line width=1.1pt] ({\c - 1}, {-\qfdNW - 3}) rectangle (\c, {-\qfdNW - 4});
  \foreach \r/\t in {1/Target, 2/Difficulty (1--5), 3/Absolute weight, 4/Relative weight \%}
    \node[anchor=east, font=\scriptsize\itshape] at (-0.1, {-\qfdNW - \r + 0.5}) {\t};
  % --- Comparative evaluation: Bluebin vs the two alternatives ---
  % Bluebin (target)
  \draw[qfdalt1ln] \bbEv{1}{5} -- \bbEv{2}{5} -- \bbEv{3}{4} -- \bbEv{4}{5}
    -- \bbEv{5}{5} -- \bbEv{6}{5} -- \bbEv{7}{4} -- \bbEv{8}{4}
    -- \bbEv{9}{5} -- \bbEv{10}{5};
  \foreach \r/\s in {1/5, 2/5, 3/4, 4/5, 5/5, 6/5, 7/4, 8/4, 9/5, 10/5}
    \node[qfdalt1mk] at \bbEv{\r}{\s} {};
  % Jira
  \draw[qfdalt2ln] \bbEv{1}{1} -- \bbEv{2}{1} -- \bbEv{3}{2} -- \bbEv{4}{2}
    -- \bbEv{5}{3} -- \bbEv{6}{1} -- \bbEv{7}{2} -- \bbEv{8}{1}
    -- \bbEv{9}{4} -- \bbEv{10}{3};
  \foreach \r/\s in {1/1, 2/1, 3/2, 4/2, 5/3, 6/1, 7/2, 8/1, 9/4, 10/3}
    \node[qfdalt2mk] at \bbEv{\r}{\s} {};
  % Linear
  \draw[qfdalt3ln] \bbEv{1}{1} -- \bbEv{2}{1} -- \bbEv{3}{2} -- \bbEv{4}{2}
    -- \bbEv{5}{4} -- \bbEv{6}{1} -- \bbEv{7}{3} -- \bbEv{8}{4}
    -- \bbEv{9}{3} -- \bbEv{10}{2};
  \foreach \r/\s in {1/1, 2/1, 3/2, 4/2, 5/4, 6/1, 7/3, 8/4, 9/3, 10/2}
    \node[qfdalt3mk] at \bbEv{\r}{\s} {};
  % Physical board + cards
  \draw[qfdalt4ln] \bbEv{1}{2} -- \bbEv{2}{3} -- \bbEv{3}{3} -- \bbEv{4}{2}
    -- \bbEv{5}{2} -- \bbEv{6}{3} -- \bbEv{7}{5} -- \bbEv{8}{5}
    -- \bbEv{9}{1} -- \bbEv{10}{5};
  \foreach \r/\s in {1/2, 2/3, 3/3, 4/2, 5/2, 6/3, 7/5, 8/5, 9/1, 10/5}
    \node[qfdalt4mk] at \bbEv{\r}{\s} {};
\end{qfdhouse}
\end{document}
```

### Where we land

The right-hand zone scores each Goal 0–5 for four alternatives. **Bluebin** is the target score, not a measurement — nothing is built yet. **Jira** and **Linear** are kept apart on purpose: they fail the lean Goals the same way but trade off against each other everywhere else — Jira buys reports and configuration with slow capture, Linear buys speed with an opinionated workflow. **Physical board** is the shop-floor baseline: a wall, cards, a Heijunka box.

| Goal                                 | Bluebin | Jira | Linear | Physical board | Reading                                                                                                          |
| ------------------------------------ | :-----: | :--: | :----: | :------------: | ---------------------------------------------------------------------------------------------------------------- |
| G1 Takt Time visible to all          |    5    |  1   |   1    |       2        | No alternative knows **Takt Time**; a board shows due dates, not a gap that moves with **Working Time**          |
| G2 Pull, every **Deviation** visible |    5    |  1   |   1    |       3        | A WIP limit can be ignored silently; a missing physical card is at least visible, but leaves no reason           |
| G3 One-piece flow at **Takt Time**   |    4    |  2   |   2    |       3        | Tooling can push the flow, not guarantee it                                                                      |
| G4 Jidoka: stop and fix              |    5    |  2   |   2    |       2        | A bug ticket at the end of the board is the opposite of stopping where the defect is found                       |
| G5 Team Member knows the next thing  |    5    |  3   | **4**  |       2        | Linear's triage and "my issues" come closest; still no **Rework**, no **Help Downstream**                        |
| G6 Levelled **Product Mix**          |    5    |  1   |   1    |       3        | The Heijunka box is physical practice; no card board levels anything                                             |
| G7 **Line** at a glance              |    4    |  2   |   3    |     **5**      | A wall wins on peripheral vision; Jira loses it to clutter; a TV screen is our answer, not a win                 |
| G8 Recording costs seconds           |    4    |  1   |   4    |     **5**      | Jira is form-heavy; Linear is keyboard-fast and ties us; we pay a click and a reason                             |
| G9 Flow problems as numbers          |    5    |  4   |   3    |       1        | Jira's reports are the closest fight; they just measure the wrong flow                                           |
| G10 Design and change without code   |    5    |  3   |   2    |     **5**      | A wall is redrawn in a minute; Jira pays an admin for it; Linear refuses; keeping that freedom in software is R1 |

Four readings:

1. **We win the lean Goals, not the board Goals.** G1, G2, G4, G6 are where nothing competes — **Takt Time**, pull with a reason, Jidoka, Heijunka. That is the product.
2. **The physical board beats us on G7, G8, G10.** These three are exactly the costs of being software. They set hard budgets: live screens (§8), recording ≤ 10 s (F31), and change-while-running (F40) even though F40 ranks last by weight and first by difficulty.
3. **Splitting the two tools splits the threat.** Jira is the threat on G9 (reports) and G10 (configuration); Linear is the threat on G5 (next thing) and G8 (speed of capture). No single competitor holds both ends, so neither one alone sets our bar — the envelope of the two does.
4. **G8 is now a tie, not a lead.** Linear scores 4 like us. The only reason we stay level is F31; if the reason prompt grows past 10 s, Linear is ahead on the Goal that every **Team Member** touches all day.

---

## 1. Goals — the WHATs

User-facing outcomes, weight 1–10, grouped by the parts of the Toyota Production System house: the roof is the goal, two pillars hold it, Team Members work in the centre, and the foundation carries everything.

```tikz
\usetikzlibrary{positioning, calc}
\definecolor{bbRoof}{HTML}{B7791F}
\definecolor{bbJit}{HTML}{2B6CB0}
\definecolor{bbJidoka}{HTML}{6B46C1}
\definecolor{bbPeople}{HTML}{B83280}
\definecolor{bbBase}{HTML}{4A5568}
\begin{document}
\hyphenpenalty=10000 \exhyphenpenalty=10000
\begin{tikzpicture}[x=1cm, y=1cm, line join=round,
  box/.style={draw=#1!80!black, line width=0.9pt, fill=#1!10},
  head/.style={font=\bfseries\small, align=center, text=#1!85!black},
  body/.style={font=\scriptsize, align=center, text width=#1 cm},
  ids/.style={font=\scriptsize\itshape, align=center}]
  % Title
  \node[font=\large\bfseries] at (7, 14.3) {Bluebin --- the TPS house};
  % Roof
  \draw[box=bbRoof] (-0.8, 9) -- (7, 13.4) -- (14.8, 9) -- cycle;
  \node[head=bbRoof] at (7, 11.25) {Roof --- Client satisfaction};
  \node[body=7.5] at (7, 10.35) {G1 Everyone is aligned on the active \textbf{Demands} and sees whether each one is on its \textbf{Takt Time} for its \textbf{Client}};
  \node[ids] at (7, 9.35) {F1--F5 \quad Takt Gap, Andon, forecast, on-time share};
  % Pillars
  \draw[box=bbJit] (0, 3) rectangle (4, 9);
  \node[head=bbJit] at (2, 8.4) {Just-In-Time};
  \node[body=3.6] at (2, 6.9) {G2 Starting work without a \textbf{Kanban} is never silent: each \textbf{Deviation} is visible};
  \node[body=3.6] at (2, 5.2) {G3 Each \textbf{Piece} flows alone at its \textbf{Demand}'s \textbf{Takt Time}};
  \node[ids] at (2, 3.5) {F6--F11};
  \draw[box=bbJidoka] (10, 3) rectangle (14, 9);
  \node[head=bbJidoka] at (12, 8.4) {Jidoka};
  \node[body=3.6] at (12, 6.6) {G4 A defect stops the flow where it is found, and its author repairs it first (\textbf{Rework})};
  \node[body=3.6] at (12, 4.8) {\textbf{Andon} button: stop the \textbf{Work Station}, call the \textbf{Team Leader}};
  \node[ids] at (12, 3.5) {F12--F16, F42};
  % Centre
  \draw[box=bbPeople, rounded corners=4pt] (4.6, 3.6) rectangle (9.4, 8.4);
  \node[head=bbPeople] at (7, 7.8) {People and teamwork};
  \node[body=4.4] at (7, 6.3) {G5 A \textbf{Team Member} always knows the next thing to do: an \textbf{Assignment}, a \textbf{Rework}, \textbf{Help Downstream}, or wait};
  \node[ids] at (7, 4.2) {F17--F22};
  % Foundation
  \draw[draw=bbBase!80!black, line width=0.9pt, fill=bbBase!22] (-0.8, 2) rectangle (14.8, 3);
  \node[head=bbBase, anchor=west] at (-0.6, 2.5) {Heijunka};
  \node[body=8.5, anchor=west, align=left] at (3.2, 2.5) {G6 The \textbf{Pieces} that leave the \textbf{Backlog} have a levelled \textbf{Product Mix}};
  \node[ids, anchor=east] at (14.6, 2.5) {F23--F26};
  \draw[draw=bbBase!80!black, line width=0.9pt, fill=bbBase!15] (-0.8, 1) rectangle (14.8, 2);
  \node[head=bbBase, anchor=west, align=left] at (-0.6, 1.5) {Stability and\\visual management};
  \node[body=8.5, anchor=west, align=left] at (3.2, 1.5) {G7 The \textbf{Line} is visible at a glance \quad G8 Recording work costs seconds};
  \node[ids, anchor=east] at (14.6, 1.5) {F27--F33};
  \draw[draw=bbBase!80!black, line width=0.9pt, fill=bbBase!8] (-0.8, 0) rectangle (14.8, 1);
  \node[head=bbBase, anchor=west] at (-0.6, 0.5) {Kaizen};
  \node[body=8.5, anchor=west, align=left] at (3.2, 0.5) {G9 Flow problems show as numbers \quad G10 Design and change the \textbf{Line} without code};
  \node[ids, anchor=east] at (14.6, 0.5) {F34--F41};
  % Deferred
  \draw[line width=0.6pt, dashed, black!55] (-0.8, -0.25) rectangle (14.8, -1.05);
  \node[font=\scriptsize\itshape, black!65] at (7, -0.65) {Standardized Work --- deferred (Definition of Done per \textbf{Work Station})};
\end{tikzpicture}
\end{document}
```

| ID                                               | Goal                                                                                                                                        | Weight | Source                             |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------- | :----: | ---------------------------------- |
| **Roof — Client satisfaction**                   |                                                                                                                                             |        |                                    |
| G1                                               | Everyone is aligned on the active **Demands** and sees, at all times, whether each one is on its **Takt Time** for its **Client**           |   10   | Session decision (2026-11-03)      |
| **Pillar — Just-In-Time**                        |                                                                                                                                             |        |                                    |
| G2                                               | Starting work without a **Kanban** is never silent: each **Deviation** is visible and has a reason                                          |   9    | Kick-off conversation (2026-11-03) |
| G3                                               | Each **Piece** flows alone and reaches production at its **Demand**'s **Takt Time**                                                         |   8    | Kick-off conversation              |
| **Pillar — Jidoka**                              |                                                                                                                                             |        |                                    |
| G4                                               | A defect stops the flow where it is found, and its author repairs it first (**Rework**)                                                     |   8    | Session decision (2026-11-03)      |
| **Centre — People and teamwork**                 |                                                                                                                                             |        |                                    |
| G5                                               | A **Team Member** always knows the next thing to do: an **Assignment**, a **Rework**, **Help Downstream**, or wait                          |   9    | Kick-off conversation              |
| G11                                              | Each **Team Member** signs in and finds their own work in every **Line** they belong to                                                     |   7    | Session decision (2026-11-06)      |
| **Foundation — Heijunka**                        |                                                                                                                                             |        |                                    |
| G6                                               | The **Pieces** that leave the **Backlog** have a levelled **Product Mix**                                                                   |   7    | Kick-off conversation              |
| **Foundation — Stability and visual management** |                                                                                                                                             |        |                                    |
| G7                                               | The whole **Line** is visible at a glance: **Kanbans**, **Blue Bins**, **Rework**, bottleneck                                               |   8    | Kick-off conversation              |
| G8                                               | Recording work costs seconds, so the data stays true                                                                                        |   8    | Kick-off conversation              |
| G12                                              | A **Line** shows only to the **Accounts** it is meant for: a **Private Line** stays private, and only the owner changes a **Line**          |   6    | Session decision (2026-11-06)      |
| **Foundation — Kaizen**                          |                                                                                                                                             |        |                                    |
| G9                                               | Flow problems show as numbers: **Lead Time**, **Stagnation Time**, **Starvation Time**, **Rework Time**                                     |   8    | Kick-off conversation              |
| G10                                              | A **Line** can be designed and changed without code: **Work Stations**, **Branches**, **Blue Bins**, **Team Members**, **Working Calendar** |   6    | Kick-off conversation              |

User segments: **Team Member** (daily work), Line designer (design and Kaizen), **Client** and Demand owner (Demands and **Takt Time**).

Deferred: **Standardized Work** (foundation). The Definition of Done of each **Work Station** stays out of the app for now. **Trigger to revisit:** **Rework** shows that **Work Stations** disagree on what "done" means.

---

## 2. Functions — the HOWs

Measurable responsibilities. Direction: ↑ higher is better, ↓ lower is better, → fixed value.

| ID                                               | Function                                                                                                                                                                                             | Dir | Target                                                        | Goal |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :-: | ------------------------------------------------------------- | ---- |
| **Roof — Client satisfaction**                   |                                                                                                                                                                                                      |     |                                                               |      |
| F1                                               | Show every active **Demand** with its **Client**, due date, **Takt Time** and **Takt Gap**, in one view that is the same for everyone                                                                |  →  | 1 shared view, open in ≤ 1 s                                  | G1   |
| F2                                               | Update the **Takt Gap** when a **Piece** reaches production, and as **Working Time** passes                                                                                                          |  ↓  | ≤ 1 min after the event                                       | G1   |
| F3                                               | Raise an **Andon** to all **Team Members** when a **Demand** falls behind its **Takt Time** (**Takt Gap** ≤ −1)                                                                                      |  ↓  | ≤ 1 min                                                       | G1   |
| F4                                               | Forecast the delivery date of each **Demand** from its current flow, and compare it with the due date                                                                                                |  ↓  | error ≤ 1 working day                                         | G1   |
| F5                                               | Measure the share of **Demands** that reach production by their due date                                                                                                                             |  ↑  | ≥ 90 %                                                        | G1   |
| **Pillar — Just-In-Time**                        |                                                                                                                                                                                                      |     |                                                               |      |
| F6                                               | Warn before a pull without a **Kanban**, and record a **Deviation** with its reason if the **Team Member** goes on                                                                                   |  →  | 100 % warned and recorded                                     | G2   |
| F7                                               | Send one **Kanban** upstream for each pull out of a **Blue Bin**, and one **Kanban** to each **Branch** for each **Assembly**                                                                        |  →  | **Kanbans** ≤ empty **Blue Bins**, at all times               | G2   |
| F8                                               | Warn before an **Assembly** when a **Sub-Piece** is not in the last **Blue Bin** of its **Branch**, and record a **Deviation** with its reason if the **Team Member** goes on                        |  →  | 100 % warned and recorded                                     | G2   |
| F9                                               | Warn before a second **Piece** goes in a **Blue Bin**, and record a **Deviation** with its reason if the **Team Member** goes on                                                                     |  →  | 100 % warned and recorded                                     | G3   |
| F10                                              | Compare the capacity of each **Work Station** (average **Touch Time** ÷ **Team Members** working) with the **Takt Time** of the **Line**, and flag the slower ones                                   |  ↓  | flag ≤ 1 working day after the change                         | G3   |
| F11                                              | Recompute the **Takt Time** of the **Line** when a **Demand** enters or ends                                                                                                                         |  ↓  | ≤ 1 min                                                       | G3   |
| **Pillar — Jidoka**                              |                                                                                                                                                                                                      |     |                                                               |      |
| F12                                              | Raise **Rework** on a **Piece**: name the **Work Station** that made the defect, and describe the defect in one line                                                                                 |  ↓  | ≤ 2 clicks, ≤ 10 s                                            | G4   |
| F13                                              | Give the **Rework** to its author by default: put it first in their **Assignments** and pause their current **Piece**                                                                                |  ↓  | ≤ 1 min after the **Rework** is raised                        | G4   |
| F14                                              | Warn before the downstream **Work Station** pulls a new **Piece** while its **Rework** is open, and record a **Deviation** if it goes on                                                             |  →  | 100 % warned and recorded                                     | G4   |
| F15                                              | Raise an **Andon** when a **Rework** waits without an active **Assignment**                                                                                                                          |  ↓  | after ≤ 1 h of **Working Time**                               | G4   |
| F16                                              | Measure, for each **Work Station**, its **Rework Time** and its **First Pass Yield**                                                                                                                 |  ↑  | **First Pass Yield** ≥ 90 %                                   | G4   |
| F42                                              | Let any **Team Member** raise an **Andon** on their **Work Station** with one button: it stops the **Work Station** and calls its **Team Leader**, who closes it                                     |  ↓  | 1 click; **Team Leader** called ≤ 1 min                       | G4   |
| **Centre — People and teamwork**                 |                                                                                                                                                                                                      |     |                                                               |      |
| F17                                              | Update the **Priority List** of each **Work Station** and the **Assignments** of each **Team Member** after any flow event                                                                           |  ↓  | ≤ 2 s                                                         | G5   |
| F18                                              | Order **Priority Lists** and **Assignments** by the glossary rules: **Rework**, then nearest to production, then oldest                                                                              |  →  | 100 % of cases                                                | G5   |
| F19                                              | Show each **Team Member** one next thing: their active **Assignment**, the top **Kanban** they can take, a **Help Downstream** target, or "wait"                                                     |  ↓  | 1 screen, ≤ 1 s                                               | G5   |
| F20                                              | Let a free **Team Member** take the top **Kanban** of their **Work Station** nearest to production                                                                                                   |  ↓  | 1 click                                                       | G5   |
| F21                                              | Let any **Team Member** of a **Work Station** reassign an **Assignment** to another **Team Member** of the same **Work Station**                                                                     |  ↓  | ≤ 2 clicks                                                    | G5   |
| F22                                              | Propose a **Help Downstream** target: the nearest downstream **Work Station** that holds up the flow (open **Rework**, or a full **Blue Bin** in front of it)                                        |  →  | always shown when the **Team Member** has no **Kanban**       | G5   |
| **Foundation — Heijunka**                        |                                                                                                                                                                                                      |     |                                                               |      |
| F23                                              | Compute the **Heijunka Sequence** from the **Takt Time** of each active **Demand**: earliest slot, then earliest due date, then first-in, first-out                                                  |  ↓  | recomputed ≤ 1 min after a **Demand** enters, ends or changes | G6   |
| F24                                              | Release the top **Piece** of the **Backlog** only when the first **Work Station** takes a **Kanban**                                                                                                 |  →  | 100 % of releases                                             | G6   |
| F25                                              | Let a **Team Member** reorder the **Heijunka Sequence** by hand as a **Deviation** with its reason, and show the effect on the **Takt Gap** and the forecast of each **Demand** before they confirm  |  ↓  | effect shown ≤ 2 s                                            | G6   |
| F26                                              | Measure, for each day, the gap between the planned and the real **Product Mix** of the **Pieces** that leave the **Backlog**                                                                         |  ↓  | ≤ 1 **Piece** for each **Demand**, each day                   | G6   |
| **Foundation — Stability and visual management** |                                                                                                                                                                                                      |     |                                                               |      |
| F27                                              | Show the **Line** view: each **Work Station** with its **Blue Bins** (full or empty), **Kanbans**, **Team Members**, active **Assignments**, open **Rework**, **Deviations** and **Andons**          |  ↓  | 1 screen, readable on a wall TV                               | G7   |
| F28                                              | Update every open view after a flow event, with no manual refresh                                                                                                                                    |  ↓  | ≤ 2 s                                                         | G7   |
| F29                                              | Highlight the bottleneck: the **Work Stations** flagged by F10, or with a full **Blue Bin** in front of them                                                                                         |  ↓  | ≤ 1 min after the change                                      | G7   |
| F30                                              | Record a flow event (pull, put in **Blue Bin**, **Assembly**, take a **Kanban**, reassign)                                                                                                           |  ↓  | ≤ 2 clicks, ≤ 5 s                                             | G8   |
| F31                                              | Record a **Deviation** reason in one line                                                                                                                                                            |  ↓  | ≤ 10 s                                                        | G8   |
| F32                                              | Pause all but one **Piece** of a **Team Member** when they take another **Assignment**: the one nearest to production stays active                                                                   |  →  | 100 %, with no manual step                                    | G8   |
| F33                                              | Show stale **Assignments**: active, with no event for more than 1 working day                                                                                                                        |  ↓  | ≤ 5 % of active **Assignments**                               | G8   |
| **Foundation — Kaizen**                          |                                                                                                                                                                                                      |     |                                                               |      |
| F34                                              | Compute **Lead Time**, **Station Lead Time**, **Touch Time** and **Stagnation Time** for each **Piece** and each **Demand**, and **Starvation Time** for each **Work Station**, from the flow events |  →  | **Lead Time** = **Touch Time** + **Stagnation Time**, exactly | G9   |
| F35                                              | Switch every measure between **Calendar Time** (the default) and **Working Time**                                                                                                                    |  ↓  | 1 click                                                       | G9   |
| F36                                              | Show, for each **Work Station**, the share of **Touch Time** in the **Station Lead Time**                                                                                                            |  ↑  | value visible for each **Work Station**                       | G9   |
| F37                                              | Show the **Deviations** for each **Work Station** and for each rule, with their reasons                                                                                                              |  ↓  | ≤ 5 % of pulls                                                | G9   |
| F38                                              | Compare two periods (before and after a **Line** change) on all measures                                                                                                                             |  ↓  | 1 view                                                        | G9   |
| F39                                              | Design a **Line**: **Work Stations**, **Splits**, **Branches**, **Assembly**, **Blue Bin** count, **Team Members**, **Working Calendar**                                                             |  ↓  | the software team example in ≤ 30 min                         | G10  |
| F40                                              | Change a **Line** while it runs (**Blue Bins**, **Team Members**, **Work Stations**), keep all past events, and date each change                                                                     |  →  | 0 lost events, 100 % of changes dated                         | G10  |
| F41                                              | Let each **Line** name its own **Demands** and **Pieces**, for example "Feature" and "User Story"                                                                                                    |  →  | free labels for each **Line**                                 | G10  |
| **Sign-in and access**                           |                                                                                                                                                                                                      |     |                                                               |      |
| F43                                              | Link a **Team Member** to an **Account** by email in Design, and show "not linked yet"                                                                                                               |  →  | 100 % linked at the next sign-in                              | G11  |
| F44                                              | Ask an **Account** for its first and last name once, filled in from the authentik name                                                                                                               |  ↓  | 1 screen, once per **Account**                                | G11  |
| F45                                              | Open the signed-in **Team Member**'s own **Assignments** after sign-in                                                                                                                               |  ↓  | 0 clicks                                                      | G11  |
| F46                                              | List in the **Line** menu every **Line** the **Account** can open, grouped by **Workspace**                                                                                                          |  →  | all of them and only them                                     | G11  |
| F47                                              | Show the **Account**'s first and last name on each linked **Team Member**, in every **Line**                                                                                                         |  →  | 100 %                                                         | G11  |
| F48                                              | Hide a **Private Line** from every **Account** that is not its owner or one of its **Team Members**                                                                                                  |  ↓  | 0 leaks (`404`)                                               | G12  |
| F49                                              | Refuse the owner-only changes (make, rename, empty, redesign, share) from any other **Account**                                                                                                      |  ↓  | 0 (`403`)                                                     | G12  |
| F50                                              | Refuse a flow action done as a **Team Member** that is not the **Account**'s own; only the owner acts for **Team Members** with no **Account**                                                       |  ↓  | 0                                                             | G12  |
| F51                                              | Choose **Shared** or **Private** in the New Line form, and change it in the **Line** menu                                                                                                            |  ↓  | ≤ 2 clicks                                                    | G12  |
| F52                                              | With SSO off, link nothing and open no other **Workspace** ([ADR-0003](./docs/adr/0003-link-team-members-to-accounts-by-email.md))                                                                   |  ↓  | 0 links                                                       | G12  |
| F53                                              | Show the **Shared Lines** of the **Public Workspace** to everyone, signed in or not, look-only; only its owner (`akadmin`) changes it                                                                |  ↓  | 0 changes by anyone else                                      | G12  |

---

## 4. Cascade — Goals → Functions → How → Components

- **G1** Client satisfaction, Takt Time visible to everyone _W:10_ — F1–F5
- **G2** Pull, every **Deviation** visible _W:9_ — F6–F9
- **G3** One-piece flow at **Takt Time** _W:8_ — F10–F11
- **G4** Jidoka, stop and fix _W:8_ — F12–F16, F42
- **G5** A **Team Member** knows the next thing to do _W:9_ — F17–F22
- **G6** Levelled **Product Mix** _W:7_ — F23–F26
- **G7** **Line** at a glance _W:8_ — F27–F29
- **G8** Recording costs seconds _W:8_ — F30–F33
- **G9** Flow problems as numbers _W:8_ — F34–F38
- **G10** Design and change without code _W:6_ — F39–F41
- **G11** A **Team Member** signs in and finds their own work _W:7_ — F43–F47
- **G12** A **Line** shows only to the **Accounts** it is meant for _W:6_ — F48–F53

Core How decisions, shared by many Functions:

- **How H3 — flow events + current state, in one transaction** (chosen, see T1)
  - Serves: F2, F34, F35, F38, F40 (history and measures), F17, F27 (fast reads)
  - Each action appends one flow event to an append-only log, and updates the current-state tables in the same transaction
  - Every measure can be recomputed from the log, for example after a **Working Calendar** change
- **How H1 — current state only** (rejected, see T1)
- **How H2 — full event sourcing** (rejected, see T1)
- **How H5 — Server-Sent Events** (chosen, see T2)
  - Serves: F2, F3, F15, F17, F27, F28 (every open screen updated in ≤ 2 s)
  - Each new flow event in the log is pushed to the open screens of its **Line**; actions still go as normal HTTP requests
  - A screen that reconnects reloads the current state; nothing is lost, because the log is the source of truth
- **How H4 — polling every 2 s** (rejected, see T2)
- **How H6 — WebSockets** (rejected, see T2)

- **How H8 — Account links in one shared `accounts.db`** (chosen, see T4 and [ADR-0004](./docs/adr/0004-account-links-live-in-one-shared-accounts-db.md))
  - Serves: F43–F47 (links, names, the Lines of an **Account**), F48–F50 (access checks)
  - Holds each **Account** (first name, last name, email) and each link (**Workspace**, **Line**, **Team Member**, email), outside the **Line** files
  - A link counts only while its **Team Member** still exists in the **Line**, so a Reset or a removed **Team Member** leaves a harmless orphan, cleaned after the change
  - Linked means an **Account** with that email exists. The **Account**'s first and last name is copied onto the linked **Team Member** in the **Line** file, as a dated rename: after each Design save, and at each sign-in, across every **Line** that has its email (F47). Every screen and measure then reads one name, with no join to `accounts.db`
- **How H10 — one access guard before every Line route and the live stream** (chosen)
  - Serves: F48–F50
  - Finds the **Account**'s role in the **Line**: owner, own **Team Member**, look-only, or none; a per-route table says which role each route needs, and a route with no entry is refused
  - A flow action acts as the **Team Member** the guard found; the `teamMember` of the request must be that **Team Member**, or one with no **Account** when the owner acts, else `403`
  - A **Private Line** answers `404` to an **Account** with no role, on the API and on the live stream alike
- **How H12 — the owner's uid names the Workspace in the URL** (chosen, see T5)
  - Serves: F45, F46, F48 (open another owner's **Workspace**)
  - API `/api/w/<owner-uid>/lines/<id>/…`, SPA `/w/<owner-uid>/lines/<id>/<view>`; the uid is already the **Workspace** directory name, so nothing moves
- **How H13 — a random Workspace id mapped in `accounts.db`** (rejected, see T5)
- **How H14 — the Line id only** (rejected: every **Workspace** has a **Line** `main`, so ids clash)
- **How H11 — a check inside each handler** (rejected: about 25 places, and a route that forgets the check is open)
- **How H7 — email on the Team Member in the Line file, plus a rebuildable index** (rejected, see T4)
- **How H9 — email in the Line files only, scanned at sign-in** (rejected, see T4)

Components that realise these How decisions:

- **C1** SPA — Vite + Vue 3 + TypeScript + Tailwind v4 + DaisyUI
- **C2** API — Gleam (wisp + mist): flow rules, **Deviations**, **Priority List** ordering, Heijunka sequencer
- **C3** Store — SQLite (sqlight): flow event log + current-state tables (H3)
- **C4** Event stream — Server-Sent Events from mist (H5)
- **C5** Deploy — Coolify, one image (the API serves the SPA), rolling updates, on bluebin.app
- **C6** Accounts store — `data/accounts.db` (H8)
- **C7** Access guard — `bluebin/access` in C2 (H10)
- **C8** Forward-auth headers — `X-authentik-email`, `X-authentik-name` (ADR-0003)

Changes to existing components for G11 and G12: C1 gets `/w/<owner-uid>/lines/<id>/<view>` URLs (H12), the **Line** menu grouped by **Workspace**, **Shared** or **Private** in the New Line form and the **Line** menu, an email and "not linked yet" on each **Team Member** in Design, a first sign-in screen for first and last name, and the own **Assignments** after sign-in. C3 gets a `shared` flag on the **Line** (additive, existing **Lines** stay **Private**), changed with a dated `line_changed` event. C2 gets the **Account** routes.

---

## 5. House — Goals × key Functions

Reduced to the 11 Functions that serve several Goals; the other Functions map to one Goal each (see §4). Importance = Goal weight as a share of the total (81). Cells: 9 strong, 3 medium, 1 weak.

|           | F2  | F3  | F6  | F7  | F13 | F17 | F23 | F28 | F30 | F34 | F40 |
| --------- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| G1 (12 %) |  9  |  9  |     |     |     |     |  3  |  3  |  3  |  3  |     |
| G2 (11 %) |     |     |  9  |  9  |     |  3  |     |     |     |     |     |
| G3 (10 %) |  3  |     |     |  3  |     |  1  |  3  |     |     |  3  |     |
| G4 (10 %) |     |  3  |     |     |  9  |  3  |     |     |     |     |     |
| G5 (11 %) |     |     |     |  3  |  3  |  9  |     |  3  |     |     |     |
| G6 (9 %)  |     |     |     |  3  |     |     |  9  |     |     |     |     |
| G7 (10 %) |     |  3  |  3  |  3  |     |     |     |  9  |     |     |     |
| G8 (10 %) |     |     |  1  |     |     |  1  |     |     |  9  |     |     |
| G9 (10 %) |     |     |     |     |     |     |     |     |  3  |  9  |  3  |
| G10 (7 %) |     |     |     |     |     |     |     |     |     |  1  |  9  |
| **Σ**     | 138 | 168 | 139 | 219 | 123 | 182 | 147 | 159 | 156 | 163 | 93  |
| **Rank**  |  9  |  3  |  8  |  1  | 10  |  2  |  7  |  5  |  6  |  4  | 11  |

**Top engineering priorities:** F7 (a **Kanban** on each pull) and F17 (**Assignments** updated) carry the pull system and the daily work of every **Team Member**; F3 (**Andon**) and F34 (exact measures) carry the roof and Kaizen. F40 ranks last but is the hardest (R1), so it gets the simplest rule: only empty **Blue Bins** and **Work Stations** can be removed.

---

## 6. Roof — Function × Function conflicts

Symbols: `⊗` strong conflict, `×` mild conflict.

| ID  | Conflict                                                                    | Strength | Mitigation                                                                                                                                                                          |
| --- | --------------------------------------------------------------------------- | :------: | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| R1  | F40 change while running vs F34 exact measures                              |    ⊗     | A change can remove only an empty **Blue Bin**, or a **Work Station** with no **Piece**; measures split at the date of the change                                                   |
| R2  | F3, F15, F42 **Andons** vs F19 one next thing                               |    ×     | **Andons** show on the wall TV and the **Demand** view; on a **Team Member**'s screen, only their own **Rework** and their **Work Station**'s **Andons** interrupt them             |
| R3  | **Deviation** reasons (F6, F8, F9, F14, F25) vs F30 recording costs seconds |    ×     | One-line reason, past reasons suggested, ≤ 10 s (F31)                                                                                                                               |
| R4  | F25 manual reorder vs F26 levelled **Product Mix**                          |    ⊗     | Accepted by design: each reorder is a **Deviation**, its cost is shown before confirmation, F26 shows the drift                                                                     |
| R5  | F13 **Rework** pauses its author vs F10 flow at **Takt Time** upstream      |    ×     | Accepted: fix first; the pause shows as **Stagnation Time**                                                                                                                         |
| R6  | F2 **Takt Gap** "as **Working Time** passes" vs H5 push on events           |    ×     | The API emits a timer event every minute of **Working Time**; SSE pushes it like a flow event                                                                                       |
| R7  | F50 act only as your own **Team Member** vs F30 recording costs seconds     |    ⊗     | Accepted by design: a linked **Team Member** acts from their own device; the wall TV, signed in as the owner, acts only for **Team Members** with no **Account** and shows everyone |
| R8  | H8 links outside the **Line**'s transaction vs F40 100 % of changes dated   |    ×     | `accounts.db` keeps its own dated log of link changes                                                                                                                               |
| R9  | F48 hide a **Private Line** vs F1 one view, the same for everyone           |    ×     | Accepted by design: a **Private Line** is the owner's choice                                                                                                                        |
| R10 | F52 link nothing with SSO off vs testing G11 in dev                         |    ×     | A server setting says SSO is on; the Vite dev proxy sends the email and name headers too, with that setting on in dev only                                                          |

---

## 7. Components

| ID  | Component                                                                             | Role                                                                                                                                           | Main Functions                   | ADR                                                                         |
| --- | ------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- | --------------------------------------------------------------------------- |
| C1  | SPA: Vite + Vue 3 + TypeScript + Tailwind v4 + DaisyUI                                | All screens: **Demands** and **Takt Gap**, **Assignments**, **Line** view (wall TV), **Line** designer, measures                               | F1, F19, F25, F27, F35, F38, F39 | —                                                                           |
| C2  | API: Gleam (wisp + mist)                                                              | HTTP actions; pull rules and **Deviations**; **Priority List** and **Assignment** ordering; Heijunka sequencer; measures                       | F6–F26, F30–F34, F40             | —                                                                           |
| C3  | Store: SQLite (sqlight)                                                               | Flow event log and current-state tables, written in one transaction                                                                            | F34, F38, F40                    | [ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md)            |
| C4  | Event stream: Server-Sent Events from mist                                            | Pushes each new flow event to the open screens                                                                                                 | F2, F3, F15, F17, F28            | —                                                                           |
| C5  | Deploy: Coolify, one image with rolling updates, bluebin.app                          | Hosting                                                                                                                                        | —                                | —                                                                           |
| C6  | Accounts store: `data/accounts.db` (sqlight)                                          | Each **Account** (uid, email, first and last name) and each link (**Workspace**, **Line**, **Team Member**, email), one email per **Line**     | F43–F47                          | [ADR-0004](./docs/adr/0004-account-links-live-in-one-shared-accounts-db.md) |
| C7  | Access guard: Gleam module `bluebin/access` in C2                                     | Role of the **Account** in the **Line**, per-route role table, `teamMember` check, `404` for a **Private Line** on the API and the live stream | F48–F50, F52                     | —                                                                           |
| C8  | Forward-auth headers: Traefik `authResponseHeaders` in the Coolify custom labels (C5) | Adds `X-authentik-email` and `X-authentik-name`, written by authentik only                                                                     | F44, F52                         | [ADR-0003](./docs/adr/0003-link-team-members-to-accounts-by-email.md)       |

---

## 8. Critical performance budget

| Rank | Function                                                 | Target                | Watched on                                                                      | If we miss it                                                                                                                                           |
| :--: | -------------------------------------------------------- | --------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
|  1   | F30 record a flow event                                  | ≤ 2 clicks, ≤ 5 s     | Time from opening the screen to confirming the action, measured in the SPA      | Quick-action button on each **Assignment**, plus keyboard shortcuts; if events are still skipped, F33 shows the gaps and the **Team Leader** fixes them |
|  2   | F17 / F28 **Assignments** and screens updated            | ≤ 2 s                 | Time from writing the event to the screen update, logged by the API and the SPA | The SPA reloads the current state when SSE is late (H4 polling as fallback)                                                                             |
|  3   | F34 **Lead Time** = **Touch Time** + **Stagnation Time** | exact                 | Nightly job that recomputes the measures from the log and compares              | The log is the truth: rebuild the current-state tables from it ([ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md))                       |
|  4   | F2 / F3 **Takt Gap** and **Andon**                       | ≤ 1 min               | Time from the timer tick or event to the **Andon** on screen                    | The **Takt Gap** is also computed when a screen opens, so a missed tick does no harm                                                                    |
|  5   | F4 delivery forecast                                     | error ≤ 1 working day | Forecast date vs real date, for each finished **Demand**                        | Show a date range, not one date, until the error goes down                                                                                              |
|  6   | F39 design the software team's **Line**                  | ≤ 30 min              | Time measured in the first real session with the team                           | Supply a "software team" template, with the **Split** for Web, iOS and Android                                                                          |

### Sign-in and access (G11, G12)

| Rank | Function                              | Target                             | Watched on                                                                                                                        | If we miss it                                                                                                               |
| :--: | ------------------------------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
|  1   | F48 / F50 access guard                | 0 leaks, 0 actions as someone else | A test that fails when a route has no role-table entry, one test for each role × route; `403` and `404` counts in the request log | Routes with no entry are refused by default; on a leak, a server setting turns links off and access goes back to owner-only |
|  2   | F43 link at the next sign-in          | 100 %                              | "Not linked yet" count in Design                                                                                                  | The owner sees the unlinked **Team Members** and fixes the email                                                            |
|  3   | Guard cost per request                | ≤ 5 ms                             | Request duration in the log, before and after                                                                                     | Cache the role for each **Account** and **Line** in memory, cleared when a link or the flag changes                         |
|  4   | F45 own **Assignments** after sign-in | 0 clicks                           | First screen after sign-in, in the SPA                                                                                            | A "My work" entry in the **Line** menu                                                                                      |

---

## 9. Tradeoffs — Got / Paid / ADR

| ID  | Tradeoff                                                                                                       | Got                                                                                                         | Paid                                                                                      | ADR                                                              |
| --- | -------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| T1  | Flow events + current state in one transaction (H3), over current state only (H1) and full event sourcing (H2) | Full history; every measure can be recomputed; dated **Line** changes; simple, fast reads for daily screens | Two writes for each action that must stay consistent; the log grows forever               | [ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md) |
| T2  | Server-Sent Events (H5), over polling (H4) and WebSockets (H6)                                                 | Updates in less than 1 s; standard browser reconnect; one direction is all we need                          | One open connection for each screen; actions and updates use two channels                 | —                                                                |
| T3  | SQLite (C3), over Postgres                                                                                     | One file, real transactions, no database server; fits the one-writer flow of a team                         | Single writer: a move to Postgres when many teams share one instance (H3 does not change) | —                                                                |

| T4 | Account links only in a shared `accounts.db` (H8), over the email on the **Team Member** in the **Line** file plus an index (H7), and a scan of the **Line** files (H9) | One place for every **Account** and link; F46 and each access check are one indexed query; no copy to keep in sync | A link change is not in the **Line**'s transaction or flow log; a Reset or a removed **Team Member** leaves orphan links, so every read checks that the **Team Member** still exists | [ADR-0004](./docs/adr/0004-account-links-live-in-one-shared-accounts-db.md) |
| T5 | The owner's uid in the URL (H12), over a random **Workspace** id (H13) | No migration, no new table: the uid is already the directory name | The owner's authentik uid (a hash) shows in links, history and logs; a **Workspace** cannot move to another owner | — |

### Tensions being watched (unresolved by design)

- **Single SQLite writer.** One instance serves one or a few teams. **Trigger to revisit:** many teams share one instance, or write latency breaks F17.
- **Standardized Work out of the app.** No Definition of Done per **Work Station**. **Trigger to revisit:** **Rework** shows that **Work Stations** disagree on what "done" means.
- **Acceptance of a whole Feature.** Each **Piece** goes to production alone; there is no **Demand**-level acceptance. **Trigger to revisit:** a **Client** cannot accept value one **Piece** at a time.
- **No personal notifications.** Only **Andons** interrupt. **Trigger to revisit:** stale **Assignments** (F33) stay above 5 %.
- **A Workspace cannot move to another owner** (T5). The owner's uid is the **Workspace** directory. **Trigger to revisit:** an owner leaves a team that keeps working.
- **The wall TV cannot act for linked Team Members** (R7). **Trigger to revisit:** stale **Assignments** (F33) above 5 % on teams with linked **Team Members**.
- **Orphan links after a Reset or a removed Team Member** (H8). Harmless, because a link counts only while its **Team Member** exists. **Trigger to revisit:** orphan links outnumber live ones, or a cleanup misses a case.
- **The Account's name is asked once, never synced from authentik** (F44). **Trigger to revisit:** people change their name in authentik and expect Bluebin to follow.

---

## 10. Inconsistencies spotted and fixed

- **Soft pull rules vs "never" in the glossary and in G2.** F6, F8 and F9 warn and do not block, but [CONTEXT.md](./CONTEXT.md) said a **Team Member** never starts work without a **Kanban**, and G2 said overproduction is impossible. Resolved: new term **Deviation** (a broken rule, with a required reason, visible at once); the glossary now says "only as a **Deviation**"; G2 now says "never silent".
- **Help Downstream target.** During the glossary session, Help Downstream was said to point at the **Work Station** with the most **Starvation Time**. A starved **Work Station** is downstream of the problem, not the problem. Resolved: F22 points at the nearest downstream **Work Station** that holds up the flow, which matches the **Help Downstream** definition.
- **Person vs Team Member.** [CONTEXT.md](./CONTEXT.md) renamed **Person** to **Team Member** (2026-11-06). Resolved everywhere: the code, the SPA text, the docs, and then in one hard rename the wire and the disk (`/api/team-members`, the JSON fields `teamMember`, `teamMemberId` and `teamMembers`, the `?teamMember=` link, the `team_member` and `station_team_member` tables, and the stored `team_member_*` changes). The schema then restarted from one version, with no data kept. Ids keep their `pe-` prefix.
- **Flow actions name any Team Member.** Each flow action takes the **Team Member** from the request body, so any client acts as anyone. Open: F50 makes the server check it against the signed-in **Account**.
- **Owner of the public Workspace.** [CONTEXT.md](./CONTEXT.md) said each **Workspace** has one owner **Account**, but the public **Workspace** of visitors who are not signed in had none, and everyone could change it. Resolved: the **Public Workspace** is the **Workspace** of one chosen **Account** (`akadmin`), which alone changes it; everyone else only looks. Today SSO guards the whole app, so visitors who are not signed in cannot reach it: the look-only routes of the **Public Workspace** need authentik unauthenticated paths.
- **Diagrams lag G11 and G12.** The TPS house (§1) and the House of Quality do not show G11, G12 or F43–F52. Open: redraw both after the build.
- **"A user has one workspace for now".** The comment in `backend/src/bluebin/workspace.gleam` and the README's "Sign-in and Workspaces" say the **Workspace** comes only from `X-authentik-uid`. Open: fixed with C7 and H12.
- **F9 and the automatic pause.** F9 also warned before a second active **Assignment**, but taking an **Assignment** pauses the current one automatically, so a second active one cannot happen. Resolved: F9 covers only the second **Piece** in a **Blue Bin**.

---

## 11. Build order — G11 and G12

Each slice ships alone, from the SPA to the store, and leaves production safe. A slice that opens a **Workspace** to another **Account** ships with its guard, never before it.

| Slice | Name                                    | Functions and components         | What ships                                                                                                                                                                                                    | Done when                                                                  |
| :---: | --------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
|   1   | The **Account** (built)                 | C6, C8, F44, F52, R10            | `data/accounts.db` with each **Account**; `X-authentik-email` and `X-authentik-name` in the Coolify labels and the Vite dev proxy; the SSO setting (`BLUEBIN_SSO=on`); the first sign-in screen               | Each **Account** gives its name once; with SSO off, no **Account** is made |
|   2   | Link a **Team Member** by email (built) | F43, F47, R8                     | An email and "not linked yet" on each **Team Member** in Design; the link made at the next sign-in, and the dated log of link changes (R8); the **Account**'s name on each linked **Team Member**             | 100 % linked at the next sign-in (§8)                                      |
|   3   | Open other **Workspaces**, guarded      | H12, C7, F46, F48, F49, F50, F51 | `/api/w/<owner-uid>/lines/<id>/…` and `/w/<owner-uid>/lines/<id>/<view>`; the access guard on every **Line** route and the live stream; the **Line** menu grouped by **Workspace**; **Shared** or **Private** | 0 leaks, 0 actions as someone else (§8); one test for each role × route    |
|   4   | My work after sign-in                   | F45                              | The signed-in **Team Member**'s own **Assignments** as the first screen                                                                                                                                       | 0 clicks (§8)                                                              |
|   5   | The **Public Workspace**, look-only     | F53                              | authentik unauthenticated paths for the look-only routes; changes only by `akadmin`                                                                                                                           | 0 changes by anyone else                                                   |

Why this order:

- **Slice 1 first.** Every other Function of G11 and G12 needs an **Account**. It changes no access, so it is safe alone. The dated log of link changes moved to slice 2, which makes the first link.
- **Slice 3 is one deploy.** Today each flow action takes the **Team Member** from the request body (§10). URLs that open another **Workspace** without the guard let any client act as anyone.
- **Slice 4 after slice 3.** The first screen must know the **Line** of the **Team Member**, and that **Line** can be in another owner's **Workspace**.

---

## How to keep this honest

- When a new ADR lands, add its components to the component map and re-score the affected rows.
- When a measurement returns numbers, update the targets and the performance budget.
- Goals change rarely; functions change with each release; matrices are recomputed when either side changes.
- If a section becomes empty after edits, delete it.
