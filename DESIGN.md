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

The right-hand zone scores each Goal 0–5 for four alternatives. The **Bluebin** column holds target scores, set before the build. **Jira** and **Linear** get one column each: they fail the lean Goals in the same way, but they differ on the other Goals. Jira gives reports and configuration, with slow capture. Linear gives speed, with an opinionated workflow. **Physical board** is the shop-floor baseline: a wall, cards and a Heijunka box.

| Goal                                 | Bluebin | Jira | Linear | Physical board | Reading                                                                                                          |
| ------------------------------------ | :-----: | :--: | :----: | :------------: | ---------------------------------------------------------------------------------------------------------------- |
| G1 Takt Time visible to all          |    5    |  1   |   1    |       2        | No alternative knows **Takt Time**; a board shows due dates, not a gap that moves with **Working Time**          |
| G2 Pull, every **Deviation** visible |    5    |  1   |   1    |       3        | A WIP limit can be ignored silently; a missing physical card is at least visible, but leaves no reason           |
| G3 One-piece flow at **Takt Time**   |    4    |  2   |   2    |       3        | Tooling can push the flow, not guarantee it                                                                      |
| G4 Jidoka: stop and fix              |    5    |  2   |   2    |       2        | A bug ticket at the end of the board is the opposite of stopping where the defect is found                       |
| G5 Team Member knows the next thing  |    5    |  3   | **4**  |       2        | Linear's triage and "my issues" come closest; still no **Rework**, no **Help Downstream**                        |
| G6 Levelled **Product Mix**          |    5    |  1   |   1    |       3        | The Heijunka box is physical practice; no card board levels anything                                             |
| G7 **Line** at a glance              |    4    |  2   |   3    |     **5**      | A wall wins on peripheral vision; Jira loses it to clutter; a TV screen only narrows the gap                     |
| G8 Recording costs seconds           |    4    |  1   |   4    |     **5**      | Jira is form-heavy; Linear is keyboard-fast and ties us; we pay a click and a reason                             |
| G9 Flow problems as numbers          |    5    |  4   |   3    |       1        | Jira's reports come closest, but they count tickets with no **Takt Time**                                        |
| G10 Design and change without code   |    5    |  3   |   2    |     **5**      | A wall is redrawn in a minute; Jira pays an admin for it; Linear refuses; keeping that freedom in software is R1 |

What the scores say:

1. Bluebin leads on G1, G2, G4 and G6 (**Takt Time**, pull with a reason, Jidoka and Heijunka), where no alternative competes. These Goals are the product.
2. The physical board beats us on G7, G8 and G10, the costs of software. They set hard budgets: live screens (§8), recording in 10 s or less (F31), and change-while-running (F40), even though F40 ranks last by weight and first by difficulty.
3. Jira is the threat on G9 (reports) and G10 (configuration); Linear is the threat on G5 (next thing) and G8 (speed of capture). Each tool is strong on one side only, so our bar is the better of the two on each Goal.
4. On G8, Linear scores 4, the same as us, and F31 alone keeps us level. If the reason prompt grows past 10 s, Linear leads on the Goal that every **Team Member** touches all day.

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

| ID                                               | Goal                                                                                                                                                                      | Weight | Source                             |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :----: | ---------------------------------- |
| **Roof — Client satisfaction**                   |                                                                                                                                                                           |        |                                    |
| G1                                               | Everyone is aligned on the active **Demands** and sees, at all times, whether each one is on its **Takt Time** for its **Client**                                         |   10   | Session decision (2026-11-03)      |
| **Pillar — Just-In-Time**                        |                                                                                                                                                                           |        |                                    |
| G2                                               | Starting work without a **Kanban** is never silent: each **Deviation** is visible and has a reason                                                                        |   9    | Kick-off conversation (2026-11-03) |
| G3                                               | Each **Piece** flows alone and is deployed at its **Demand**'s **Takt Time**                                                                                              |   8    | Kick-off conversation              |
| **Pillar — Jidoka**                              |                                                                                                                                                                           |        |                                    |
| G4                                               | A defect stops the flow where it is found, its author repairs it first (**Rework**), and the **Work Station** that found it helps the repair                                                                                   |   8    | Session decision (2026-11-03)      |
| **Centre — People and teamwork**                 |                                                                                                                                                                           |        |                                    |
| G5                                               | A **Team Member** always knows the next thing to do: an **Assignment**, a **Rework**, **Help the Rework**, **Help Downstream**, or wait                                                        |   9    | Kick-off conversation              |
| G11                                              | Each **Team Member** signs in and finds their own work in every **Line** they belong to                                                                                   |   7    | Session decision (2026-11-06)      |
| **Foundation — Heijunka**                        |                                                                                                                                                                           |        |                                    |
| G6                                               | The **Pieces** that leave the **Backlog** have a levelled **Product Mix**                                                                                                 |   7    | Kick-off conversation              |
| **Foundation — Stability and visual management** |                                                                                                                                                                           |        |                                    |
| G7                                               | The whole **Line** is visible at a glance: **Kanbans**, **Blue Bins**, **Rework**, bottleneck                                                                             |   8    | Kick-off conversation              |
| G8                                               | Recording work costs seconds, so the data stays true                                                                                                                      |   8    | Kick-off conversation              |
| G12                                              | A **Line** shows only to the **Accounts** it is meant for: a **Private Line** stays private, and only the owner changes a **Line**                                        |   6    | Session decision (2026-11-06)      |
| **Foundation — Kaizen**                          |                                                                                                                                                                           |        |                                    |
| G9                                               | Flow problems show as numbers: **Lead Time**, **Stagnation Time**, **Starvation Time**, **Rework Time**                                                                   |   8    | Kick-off conversation              |
| G10                                              | A **Line** can be designed and changed without code: **Work Stations**, **Branches**, **Blue Bins**, **Team Members**, **Working Calendar**                               |   6    | Kick-off conversation              |
| G13                                              | A **Team Member** can hold a deployed **Piece** for a later **Release**, and the wait until **Release** shows in the **Lead Time** of the **Piece** and of its **Demand** |   6    | Session decision 2026-11-08        |

User segments: **Team Member** (daily work), Line designer (design and Kaizen), **Client** and Demand owner (Demands and **Takt Time**).

Deferred: **Standardized Work** (foundation). The Definition of Done of each **Work Station** stays out of the app for now. **Trigger to revisit:** **Rework** shows that **Work Stations** disagree on what "done" means.

---

## 2. Functions — the HOWs

Measurable responsibilities. Direction: ↑ higher is better, ↓ lower is better, → fixed value.

| ID                                               | Function                                                                                                                                                                                                                                                                                                        | Dir | Target                                                                     | Goal |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :-: | -------------------------------------------------------------------------- | ---- |
| **Roof — Client satisfaction**                   |                                                                                                                                                                                                                                                                                                                 |     |                                                                            |      |
| F1                                               | Show every active **Demand** with its **Client**, due date, **Takt Time** and **Takt Gap**, in one view that is the same for everyone                                                                                                                                                                           |  →  | 1 shared view, open in ≤ 1 s                                               | G1   |
| F2                                               | Update the **Takt Gap** when a **Piece** is deployed, and as **Working Time** passes                                                                                                                                                                                                                            |  ↓  | ≤ 1 min after the event                                                    | G1   |
| F3                                               | Raise an **Andon** to all **Team Members** when a **Demand** falls behind its **Takt Time** (**Takt Gap** ≤ −1)                                                                                                                                                                                                 |  ↓  | ≤ 1 min                                                                    | G1   |
| F4                                               | Forecast the day each **Demand** has its last **Piece** deployed, from its current flow, and compare it with the due date                                                                                                                                                                                       |  ↓  | error ≤ 1 working day                                                      | G1   |
| F5                                               | Measure the share of **Demands** whose last **Piece** is released by their due date                                                                                                                                                                                                                             |  ↑  | ≥ 90 %                                                                     | G1   |
| **Pillar — Just-In-Time**                        |                                                                                                                                                                                                                                                                                                                 |     |                                                                            |      |
| F6                                               | Warn before a pull without a **Kanban**, and record a **Deviation** with its reason if the **Team Member** goes on                                                                                                                                                                                              |  →  | 100 % warned and recorded                                                  | G2   |
| F7                                               | Send one **Kanban** upstream for each pull out of a **Blue Bin**, and one **Kanban** to each **Branch** for each **Assembly**                                                                                                                                                                                   |  →  | **Kanbans** ≤ empty **Blue Bins**, at all times                            | G2   |
| F8                                               | Warn before an **Assembly** when a **Sub-Piece** is not in the last **Blue Bin** of its **Branch**, and record a **Deviation** with its reason if the **Team Member** goes on                                                                                                                                   |  →  | 100 % warned and recorded                                                  | G2   |
| F9                                               | Warn before a second **Piece** goes in a **Blue Bin**, and record a **Deviation** with its reason if the **Team Member** goes on                                                                                                                                                                                |  →  | 100 % warned and recorded                                                  | G3   |
| F10                                              | Compare the capacity of each **Work Station** (average **Touch Time** ÷ **Team Members** working) with the **Takt Time** of the **Line**, and flag the slower ones                                                                                                                                              |  ↓  | flag ≤ 1 working day after the change                                      | G3   |
| F11                                              | Recompute the **Takt Time** of the **Line** when a **Demand** enters or ends                                                                                                                                                                                                                                    |  ↓  | ≤ 1 min                                                                    | G3   |
| F55                                              | Suggest, for each **Work Station**, the **Blue Bin** count that covers its **Replenishment Time** at the **Takt Time** of the **Line**, and show it in Design without applying it                                                                                                                               |  →  | shown for each **Work Station** with ≥ 5 passes; ≤ 1 min after a pass ends | G3   |
| **Pillar — Jidoka**                              |                                                                                                                                                                                                                                                                                                                 |     |                                                                            |      |
| F12                                              | Raise **Rework** on a **Piece**: name the **Work Station** that made the defect, and describe the defect in one line                                                                                                                                                                                            |  ↓  | ≤ 2 clicks, ≤ 10 s                                                         | G4   |
| F13                                              | Give the **Rework** to its author by default: put it first in their **Assignments** and pause their current **Piece**                                                                                                                                                                                           |  ↓  | ≤ 1 min after the **Rework** is raised                                     | G4   |
| F14 | Warn before the downstream **Work Station** pulls a new **Piece** while its **Rework** is open; offer **Help the Rework** as the first action, and record a **Deviation** only if the **Team Member** goes on | → | 100 % warned and recorded; **Help the Rework** 1 click from the warning | G4 |
| F15                                              | Raise an **Andon** when a **Rework** waits without an active **Assignment**                                                                                                                                                                                                                                     |  ↓  | after ≤ 1 h of **Working Time**                                            | G4   |
| F16                                              | Measure, for each **Work Station**, its **Rework Time** and its **First Pass Yield**                                                                                                                                                                                                                            |  ↑  | **First Pass Yield** ≥ 90 %                                                | G4   |
| F42                                              | Let any **Team Member** raise an **Andon** on their **Work Station** with one button: it stops the **Work Station** and calls its **Team Leader**, who closes it                                                                                                                                                |  ↓  | 1 click; **Team Leader** called ≤ 1 min                                    | G4   |
| **Centre — People and teamwork**                 |                                                                                                                                                                                                                                                                                                                 |     |                                                                            |      |
| F17                                              | Update the **Priority List** of each **Work Station** and the **Assignments** of each **Team Member** after any flow event                                                                                                                                                                                      |  ↓  | ≤ 2 s                                                                      | G5   |
| F18                                              | Order **Priority Lists** and **Assignments** by the glossary rules: **Rework**, then nearest to **Deployment**, then oldest                                                                                                                                                                                     |  →  | 100 % of cases                                                             | G5   |
| F19 | Show each **Team Member** one next thing: their active **Assignment**, the top **Kanban** they can take, **Help the Rework** (before **Help Downstream**, for a **Team Member** of a stopped **Work Station**), a **Help Downstream** target, or "wait" | ↓ | 1 screen, ≤ 1 s | G5 |
| F20                                              | Let a free **Team Member** take the top **Kanban** of their **Work Station** nearest to **Deployment**                                                                                                                                                                                                          |  ↓  | 1 click                                                                    | G5   |
| F21                                              | Let any **Team Member** of a **Work Station** reassign an **Assignment** to another **Team Member** of the same **Work Station**                                                                                                                                                                                |  ↓  | ≤ 2 clicks                                                                 | G5   |
| F22 | Propose a **Help Downstream** target: the nearest downstream **Work Station** that holds up the flow with a full **Blue Bin** in front of it; never a **Work Station** stopped by its own open **Rework**, which is for **Help the Rework** (F19, F61) | → | always shown when the **Team Member** has no **Kanban** and a target exists | G5 |
| **Foundation — Heijunka**                        |                                                                                                                                                                                                                                                                                                                 |     |                                                                            |      |
| F23                                              | Compute the **Heijunka Sequence** from the remaining rate of each active **Demand** (ADR 0005): earliest slot, then earliest due date, then first-in, first-out                                                                                                                                                 |  ↓  | recomputed ≤ 1 min after a **Demand** enters, ends or changes              | G6   |
| F24                                              | Let the top **Piece** leave the **Backlog** only when the first **Work Station** takes a **Kanban**                                                                                                                                                                                                             |  →  | 100 % of releases                                                          | G6   |
| F25                                              | Let a **Team Member** reorder the **Heijunka Sequence** by hand as a **Deviation** with its reason, and show the effect on the **Takt Gap** and the forecast of each **Demand** before they confirm                                                                                                             |  ↓  | effect shown ≤ 2 s                                                         | G6   |
| F26                                              | Measure, for each day, the gap between the planned and the real **Product Mix** of the **Pieces** that leave the **Backlog**                                                                                                                                                                                    |  ↓  | ≤ 1 **Piece** for each **Demand**, each day and over the days shown     | G6   |
| **Foundation — Stability and visual management** |                                                                                                                                                                                                                                                                                                                 |     |                                                                            |      |
| F27                                              | Show the **Line** view: each **Work Station** with its **Blue Bins** (full or empty), **Kanbans**, **Team Members**, active **Assignments**, open **Rework**, **Deviations** and **Andons**                                                                                                                     |  ↓  | 1 screen, readable on a wall TV                                            | G7   |
| F28                                              | Update every open view after a flow event, with no manual refresh                                                                                                                                                                                                                                               |  ↓  | ≤ 2 s                                                                      | G7   |
| F29                                              | Highlight the bottleneck: the **Work Stations** flagged by F10, or with a full **Blue Bin** in front of them                                                                                                                                                                                                    |  ↓  | ≤ 1 min after the change                                                   | G7   |
| F30                                              | Record a flow event (pull, put in **Blue Bin**, **Assembly**, take a **Kanban**, reassign)                                                                                                                                                                                                                      |  ↓  | ≤ 2 clicks, ≤ 5 s                                                          | G8   |
| F31                                              | Record a **Deviation** reason in one line                                                                                                                                                                                                                                                                       |  ↓  | ≤ 10 s                                                                     | G8   |
| F32                                              | Pause all but one **Piece** of a **Team Member** when they take another **Assignment**: the one nearest to **Deployment** stays active                                                                                                                                                                          |  →  | 100 %, with no manual step                                                 | G8   |
| F33                                              | Show stale **Assignments**: active, with no event for more than 1 working day                                                                                                                                                                                                                                   |  ↓  | ≤ 5 % of active **Assignments**                                            | G8   |
| **Foundation — Kaizen**                          |                                                                                                                                                                                                                                                                                                                 |     |                                                                            |      |
| F34                                              | Compute **Lead Time**, **Station Lead Time**, **Touch Time** and **Stagnation Time** for each **Piece** and each **Demand**, and **Starvation Time** for each **Work Station**, from the flow events; **Lead Time** ends at **Release**, and the wait from **Deployment** to **Release** is **Stagnation Time** |  →  | **Lead Time** = **Touch Time** + **Stagnation Time**, exactly              | G9   |
| F35                                              | Switch every measure between **Calendar Time** (the default) and **Working Time**                                                                                                                                                                                                                               |  ↓  | 1 click                                                                    | G9   |
| F36                                              | Show, for each **Work Station**, the share of **Touch Time** in the **Station Lead Time**                                                                                                                                                                                                                       |  ↑  | value visible for each **Work Station**                                    | G9   |
| F37                                              | Show the **Deviations** for each **Work Station** and for each rule, with their reasons                                                                                                                                                                                                                         |  ↓  | ≤ 5 % of pulls                                                             | G9   |
| F38                                              | Compare two periods (before and after a **Line** change) on all measures                                                                                                                                                                                                                                        |  ↓  | 1 view                                                                     | G9   |
| F54                                              | Measure, for each **Work Station**, its **Replenishment Time** (85th percentile, **Working Time**) from the flow events                                                                                                                                                                                         |  →  | value for each **Work Station** with ≥ 5 passes in the period              | G9   |
| F39                                              | Design a **Line**: **Work Stations**, **Splits**, **Branches**, **Assembly**, **Blue Bin** count, **Team Members**, **Working Calendar**                                                                                                                                                                        |  ↓  | the software team example in ≤ 30 min                                      | G10  |
| F40                                              | Change a **Line** while it runs (**Blue Bins**, **Team Members**, **Work Stations**), keep all past events, and date each change                                                                                                                                                                                |  →  | 0 lost events, 100 % of changes dated                                      | G10  |
| F41                                              | Let each **Line** name its own **Demands** and **Pieces**, for example "Feature" and "User Story"                                                                                                                                                                                                               |  →  | free labels for each **Line**                                              | G10  |
| **Sign-in and access**                           |                                                                                                                                                                                                                                                                                                                 |     |                                                                            |      |
| F43                                              | Link a **Team Member** to an **Account** by email in Design, and show "not linked yet"                                                                                                                                                                                                                          |  →  | 100 % linked at the next sign-in                                           | G11  |
| F44                                              | Ask an **Account** for its first and last name once, filled in from the authentik name                                                                                                                                                                                                                          |  ↓  | 1 screen, once per **Account**                                             | G11  |
| F45                                              | Open the signed-in **Team Member**'s own **Assignments** after sign-in                                                                                                                                                                                                                                          |  ↓  | 0 clicks                                                                   | G11  |
| F46                                              | List in the **Line** menu every **Line** the **Account** can open, grouped by **Workspace**                                                                                                                                                                                                                     |  →  | all of them and only them                                                  | G11  |
| F47                                              | Show the **Account**'s first and last name on each linked **Team Member**, in every **Line**                                                                                                                                                                                                                    |  →  | 100 %                                                                      | G11  |
| F48                                              | Hide a **Private Line** from every **Account** that is not its owner or one of its **Team Members**                                                                                                                                                                                                             |  ↓  | 0 leaks (`404`)                                                            | G12  |
| F49                                              | Refuse the owner-only changes (make, rename, empty, redesign, share) from any other **Account**                                                                                                                                                                                                                 |  ↓  | 0 (`403`)                                                                  | G12  |
| F50                                              | Refuse a flow action done as a **Team Member** that is not the **Account**'s own; only the owner acts for **Team Members** with no **Account**                                                                                                                                                                  |  ↓  | 0                                                                          | G12  |
| F51                                              | Choose **Shared** or **Private** in the New Line form, and change it in the **Line** menu                                                                                                                                                                                                                       |  ↓  | ≤ 2 clicks                                                                 | G12  |
| F52                                              | With SSO off, link nothing and open no other **Workspace** ([ADR-0003](./docs/adr/0003-link-team-members-to-accounts-by-email.md))                                                                                                                                                                              |  ↓  | 0 links                                                                    | G12  |
| F53                                              | Show every **Shared Line** to anyone with its link, signed in or not, look-only; only its owner changes it                                                                                                                                                                                                      |  ↓  | 0 changes by anyone else                                                   | G12  |
| **Deployment and Release**                       |                                                                                                                                                                                                                                                                                                                 |     |                                                                            |      |
| F56                                              | Record the **Deployment** and the **Release** of a **Piece** together, with one click, by default                                                                                                                                                                                                               |  ↓  | 1 click, as Deliver today                                                  | G8   |
| F57                                              | Let a **Team Member** hold a **Piece** at its **Deployment** for a later **Release**                                                                                                                                                                                                                            |  ↓  | ≤ 2 clicks                                                                 | G13  |
| F58                                              | Release held **Pieces**, one at a time or several together, for example all held **Pieces** of one **Demand**                                                                                                                                                                                                   |  ↓  | 1 click for each **Release**, any number of **Pieces**                     | G13  |
| F59                                              | Show every held **Piece** and its wait since **Deployment** to everyone on the **Line**                                                                                                                                                                                                                         |  ↑  | 100 % of held **Pieces**, with no click                                    | G13  |
| F60                                              | Keep a **Demand** in the **Takt Time** of the **Line** until the **Release** of its last **Piece**, and mark it delivered at that **Release**                                                                                                                                                                   |  →  | exactly at that event                                                      | G13  |
| **Helpers** | | | | |
| F61 | Let a **Team Member** join a **Piece** as **Helper** by **Help the Rework**, only when they belong to the **Work Station** that found the defect or the one that made it, and someone holds the **Assignment** | ↓ | 1 click, from the stop warning (F14) or the **Rework** card | G4 |
| F62 | Pause the **Helper**'s active **Assignment** when they join; when the help ends, make their paused **Assignment** nearest to **Deployment** active again | → | 100 %, with no manual step | G8 |
| F63 | End the help at the latest when its cause ends (**Rework** closed, or **Piece** put in a **Blue Bin**), and let the **Helper** stop before | → | 0 **Helpers** after the cause ends; stop in 1 click | G8 |
| F64 | Show the **Helpers** of a **Piece** in the **Line** view, on the **Rework** card, and in the **Helper**'s own **Assignments** | ↑ | 100 % of **Helpers** visible, with no click | G7 |
| F65 | Show every **Team Member** of the **Line** with all their **Assignments** (active, paused, waiting **Rework**), what they help, and the **Pieces** and **Rework** nobody holds, so the team sees where work piles up and reassigns it (F21) | ↑ | all **Team Members** on 1 screen, ≤ 2 s after a flow event | G7 |

---

## 4. Cascade — Goals → Functions → How → Components

- **G1** Client satisfaction, Takt Time visible to everyone _W:10_ — F1–F5
- **G2** Pull, every **Deviation** visible _W:9_ — F6–F9
- **G3** One-piece flow at **Takt Time** _W:8_ — F10–F11, F55
- **G4** Jidoka, stop and fix _W:8_ — F12–F16, F42, F61
- **G5** A **Team Member** knows the next thing to do _W:9_ — F17–F22
- **G6** Levelled **Product Mix** _W:7_ — F23–F26
- **G7** **Line** at a glance _W:8_ — F27–F29, F64, F65
- **G8** Recording costs seconds _W:8_ — F30–F33, F62, F63
- **G9** Flow problems as numbers _W:8_ — F34–F38, F54
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
- **How H15 — Replenishment Time from the passes, p85 of the last 20** (chosen, see T6)
  - Serves: F54, F55
  - A pass gives the pull-in; its `piece_put_in_blue_bin` gives the end. **Rework** done later is not counted: it does not delay the **Blue Bin**
  - F55 reads the last 20 passes that ended at the **Work Station**, and needs at least 5; F54 reads the passes of the Measures period, like every other measure
  - F55 drops the pauses caused by a **Team Member** holding another **Piece** (`piece_paused` cause `held`, R11); it keeps the pauses for **Rework**, a real loss of capacity. A past pause with no cause counts as `held`. F54 shows the full **Replenishment Time**
  - Suggested **Blue Bins** = max(1, ⌈p85 **Replenishment Time** ÷ **Takt Time** of the **Line**⌉), both in **Working Time**; no suggestion when no **Demand** is active
  - Every **Piece** crosses every **Branch** (each **Branch** pulls its own **Sub-Piece**), so one **Takt Time** of the **Line** serves all **Work Stations**
  - Computed in C2, next to the F10 capacity, and sent with the Design payload: C1 holds no formula
  - C1 shows it under the **Blue Bin** input of each **Work Station** in Design, always when there is data, with its inputs: `Suggested: 3 · Takt 4 h, Replenishment 10 h (p85 of 12 passes)`. One click sets the input; the owner still saves. Neutral style: red and green are for status only
- **How H16 — the last 7 days, like F10** (rejected: a slow **Line** gets fewer than 5 passes a week)
- **How H17 — the Measures period** (rejected: Design has no period, so the suggestion would hang on hidden state)
- **How H18 — the Toyota loop**: from the **Kanban** sent, without **Starvation Time** (rejected, see T6)
- **How H19 — a `released_at` column on `piece` and a `piece_released` flow event** (chosen, see T9)
  - Serves: F56, F57, F58, F59, F60, and the **Release** end of F5 and F34
  - Deliver writes the **Deployment** and the **Release** in one transaction (F56); hold writes only the **Deployment** (F57)
  - A held **Piece** = deployed, with `released_at` empty. "Released together" (F58) = one action that writes one `piece_released` event for each **Piece**, at the same moment
  - **Lead Time** = `entered_at` → `released_at`; the wait from **Deployment** to **Release** falls into **Stagnation Time** because nobody touches the **Piece**
- **How H20 — new `held` and `released` states on `piece`** (rejected: the state repeats what the two timestamps say, and each query on the current state must change)
- **How H21 — a `release` table that groups Pieces** (rejected: no measure and no glossary rule needs the group; H19 can grow into it with no data loss)
- **How H22 — squash the schema to version 2, with no migration step, and rename `produced` to `deployed` on disk and on the wire** (chosen, see T10)
  - `piece.state` `produced` → `deployed`, `produced_at` → `deployed_at`, event `piece_reached_production` → `piece_deployed`, JSON `piecesProduced` → `piecesDeployed`
  - Workspace files at version 1 are refused: delete `/app/data/workspaces` after the deploy, as for `a5628dc`
- **How H23 — one migration step v1 → v2 with the rename** (rejected, see T10)
- **How H24 — one migration step v1 → v2, keep the `produced` names** (rejected: the code would say "produced" where the glossary says **Deployment**)
- **How H25 — a `helper` table, plus `helper_joined` and `helper_left` flow events** (chosen)
  - Serves: F61–F64
  - One row for each **Helper**: `piece_id`, `team_member_id`, `rework_id`, `since`; a unique `team_member_id` keeps one helped **Piece** at a time. The row goes when the help ends
  - `rework_id` names the cause: closing a **Rework** removes its **Helpers** (F63). **Help Downstream** can use the same table later, with no `rework_id`
  - `flow.settle` gets a third case: a **Helper** has their **Pieces** paused with the cause `helping`; with no help and no **Rework**, the next **Piece** resumes as today (F62)
- **How H26 — Helpers from the flow events only** (rejected: each **Line** view and each `settle` would scan the log, against [ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md))
- **How H27 — one `helper` column on `piece`** (rejected: a **Piece** has zero or more **Helpers**)
- **How H29 — the first migration step, v2 → v3, additive only** (chosen, see T11 and [ADR-0006](./docs/adr/0006-additive-schema-changes-migrate.md))
  - Serves: F61–F64 on the workspaces that exist
  - `prepare` runs each step from the file's version to `schema_version`, in one transaction; v2 → v3 adds the `helper` table. A step that renames or removes is still refused
- **How H28 — raise to version 3 and wipe the workspaces** (rejected, see T11)
- **How H30 — `create table if not exists` on each open, version 2 kept** (rejected: the version no longer describes the schema)

Components that realise these How decisions:

- **C1** SPA — Vite + Vue 3 + TypeScript + Tailwind v4 + DaisyUI
- **C2** API — Gleam (wisp + mist): flow rules, **Deviations**, **Priority List** ordering, Heijunka sequencer
- **C3** Store — SQLite (sqlight): flow event log + current-state tables (H3)
- **C4** Event stream — Server-Sent Events from mist (H5)
- **C5** Deploy — Coolify, one image (the API serves the SPA), rolling updates, on bluebin.app
- **C6** Accounts store — `data/accounts.db` (H8)
- **C7** Access guard — `bluebin/access` in C2 (H10)
- **C8** Forward-auth headers — `X-authentik-email`, `X-authentik-name` (ADR-0003)

Changes to existing components for G11 and G12: C1 gets `/w/<owner-uid>/lines/<id>/<view>` URLs (H12), the **Line** menu grouped by **Workspace**, **Shared** or **Private** in the New Line form and the **Line** menu, an email and "not linked yet" on each **Team Member** in Design, a first sign-in screen for first and last name, and the own **Assignments** after sign-in. C6 gets the **Shared** flag of each **Line** as a dated log (`line_share_change`, the last row wins; existing **Lines** stay **Private**), not C3: a new **Line** schema version would make the old container refuse every **Line** during a rolling deploy. C2 gets the **Account** routes.

Changes to existing components for G13: C1 `WorkStationCard` turns **Deliver** into **Deploy** (deploys and releases, F56) and adds **Deploy, hold** (F57); C1 `LineView` gets a **Held for Release** zone after the last **Work Station**, with each held **Piece**, its **Demand**, its wait since **Deployment** (F59), **Release** on each **Piece** and **Release all** on each **Demand** (F58); C1 `BacklogView` says "Move this Piece to the top" instead of "Release this Piece before its turn"; C2 `flow` turns `deliver` into `deploy(hold)` and adds `release(pieces)`, and marks a **Demand** delivered at its last **Release** (F60); C2 `measures` ends **Lead Time** and On-Time Delivery at `released_at` (F5, F34); C2 API turns `POST /api/deliver` into `POST /api/deploy` with `hold`, and adds `POST /api/release`; C3 gets the H22 schema.

Changes to existing components for Helpers (F14, F19, F61–F64): C3 gets the `helper` table through the v2 → v3 step (H29); C2 `flow` adds `help_the_rework(rework, team_member)`, which checks that the **Team Member** belongs to the **Work Station** that found the defect or the one that made it and that someone holds the **Assignment**, and `stop_helping(team_member)`; `repair_rework` removes its **Helpers** and settles each one; `settle` pauses a **Helper**'s **Pieces** with the cause `helping`; C2 `line` gives each open **Rework** the id of the **Work Station** that found it, so the SPA builds the help offers of the `pull_with_an_open_rework` warning from the **Line** it already holds; C2 `assignment` adds `HelpTheRework(rework, piece, assignee, station)`, before `HelpDownstream`, and `help_downstream` no longer targets a **Work Station** stopped by its open **Rework** (F22); C2 API adds `POST /api/help` and `POST /api/help/stop`, guarded by C7 as for F50; C1 `DeviationDialog` shows "Help <assignee> on <Piece>" for each open **Rework** as the first action, and opens the reason only after "Go on anyway (Deviation)"; C1 `WorkStationCard` adds **Help** on a **Rework** item for the **Team Members** allowed, the **Helpers**' names on the **Rework** and on the **Piece** in hand, and **Stop helping**; C1 `NextThingView` adds the kind `help_the_rework` and "Helping <assignee> on <Piece>". C4 needs no change: `helper_joined` and `helper_left` are flow events, so they are already pushed.

Changes to existing components for the comparison around a **Line** change (F38, F40): C2 `design` adds `line_changes`, which reads the `line_changed` events, groups the events of one save, drops renames and labels, and says what changed for each **Work Station** or **Team Member** ("UAT: Blue Bins 2 → 1"); C2 API adds `GET /api/line-changes`, read access; C1 `MeasuresView` picks a **Line** change and a length (7, 14 or 28 days), and makes Before end the day before the change and After start on its day, both of the same length (shorter while the change is recent); it warns when another **Line** change falls in the periods, and, with custom dates, when the two lengths differ.

Changes to existing components for the run chart (F38): C2 `measures` adds `weekly`, which gives the Line's first day (the day of its first flow event) and, reading the log once, each of the last weeks (Monday to Sunday, UTC) its Pieces released and their average **Lead Time**; C2 API adds `GET /api/measures/weeks?weeks=12` (4 to 52), read access; C1 `RunChart` draws **Lead Time** week by week with a vertical line at each **Line** change and the XmR natural limits (average ± 2.66 × the average moving range) of the full weeks before the chosen change, or of all full weeks with custom dates; it circles a signal (Wheeler rule 1: outside a limit; rule 3: 3 of 4 weeks past halfway to one) and counts the signals since the change. Poka-yoke on the periods: C1 `MeasuresView` limits each date to the days from the Line's first day to today, reads no measure while a period is out of them and says why; around a change, both periods also get shorter so that Before does not start before the Line; on a Line younger than the default periods, its days so far are split in two halves.

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

| ID  | Conflict                                                                    | Strength | Mitigation                                                                                                                                                                                                                                                                        |
| --- | --------------------------------------------------------------------------- | :------: | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| R1  | F40 change while running vs F34 exact measures                              |    ⊗     | A change can remove only an empty **Blue Bin**, or a **Work Station** with no **Piece**; measures split at the date of the change                                                                                                                                                 |
| R2  | F3, F15, F42 **Andons** vs F19 one next thing                               |    ×     | **Andons** show on the wall TV and the **Demand** view; on a **Team Member**'s screen, only their own **Rework** and their **Work Station**'s **Andons** interrupt them                                                                                                           |
| R3  | **Deviation** reasons (F6, F8, F9, F14, F25) vs F30 recording costs seconds |    ×     | One-line reason, past reasons suggested, ≤ 10 s (F31)                                                                                                                                                                                                                             |
| R4  | F25 manual reorder vs F26 levelled **Product Mix**                          |    ⊗     | Accepted by design: each reorder is a **Deviation**, its cost is shown before confirmation, F26 shows the drift                                                                                                                                                                   |
| R5  | F13 **Rework** pauses its author vs F10 flow at **Takt Time** upstream      |    ×     | Accepted: fix first; the pause shows as **Stagnation Time**                                                                                                                                                                                                                       |
| R6  | F2 **Takt Gap** "as **Working Time** passes" vs H5 push on events           |    ×     | The API emits a timer event every minute of **Working Time**; SSE pushes it like a flow event                                                                                                                                                                                     |
| R7  | F50 act only as your own **Team Member** vs F30 recording costs seconds     |    ⊗     | Accepted by design: a linked **Team Member** acts from their own device; the wall TV, signed in as the owner, acts only for **Team Members** with no **Account** and shows everyone                                                                                               |
| R8  | H8 links outside the **Line**'s transaction vs F40 100 % of changes dated   |    ×     | `accounts.db` keeps its own dated log of link changes                                                                                                                                                                                                                             |
| R9  | F48 hide a **Private Line** vs F1 one view, the same for everyone           |    ×     | Accepted by design: a **Private Line** is the owner's choice                                                                                                                                                                                                                      |
| R10 | F52 link nothing with SSO off vs testing G11 in dev                         |    ×     | A server setting says SSO is on; the Vite dev proxy sends the email and name headers too, with that setting on in dev only                                                                                                                                                        |
| R11 | F55 suggested **Blue Bins** vs F32 pause all but one **Piece**              |    ⊗     | More **Blue Bins** let a **Team Member** hold more **Pieces**; the held ones pause, the **Replenishment Time** grows, and the suggestion grows with it. Broken at the source: each `piece_paused` names its cause (`rework` or `held`), and F55 drops the `held` pauses (H15, T8) |
| R12 | F55 suggested **Blue Bins** vs F10 capacity at **Takt Time**                |    ×     | H15 sizes **Blue Bins** as if capacity were enough. A **Work Station** slower than **Takt Time** needs **Team Members** or less work, not more **Blue Bins**: F10 and F29 flag it; the suggestion does not try to                                                                 |
| R13 | F55 last 20 passes vs F40 change while running                              |    ×     | After a change (a new **Team Member**, a new **Branch**), the suggestion still reads the passes from before it. Accepted: the window renews in 20 passes; the hint shows how many passes it read                                                                                  |
| R14 | F62 pause a **Helper**'s **Pieces** vs F55 suggested **Blue Bins** | × | The pause names its cause `helping`; F55 keeps it like `rework`, because the capacity was lost to a defect, not to WIP (T12) |

---

## 7. Components

| ID  | Component                                                                             | Role                                                                                                                                                                                    | Main Functions                   | ADR                                                                         |
| --- | ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- | --------------------------------------------------------------------------- |
| C1  | SPA: Vite + Vue 3 + TypeScript + Tailwind v4 + DaisyUI                                | All screens: **Demands** and **Takt Gap**, **Assignments**, **Line** view (wall TV), **Line** designer, measures                                                                        | F1, F19, F25, F27, F35, F38, F39 | —                                                                           |
| C2  | API: Gleam (wisp + mist)                                                              | HTTP actions; pull rules and **Deviations**; **Priority List** and **Assignment** ordering; Heijunka sequencer; measures                                                                | F6–F26, F30–F34, F40             | —                                                                           |
| C3  | Store: SQLite (sqlight)                                                               | Flow event log and current-state tables, written in one transaction                                                                                                                     | F34, F38, F40                    | [ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md)            |
| C4  | Event stream: Server-Sent Events from mist                                            | Pushes each new flow event to the open screens                                                                                                                                          | F2, F3, F15, F17, F28            | —                                                                           |
| C5  | Deploy: Coolify, one image with rolling updates, bluebin.app                          | Hosting                                                                                                                                                                                 | —                                | —                                                                           |
| C6  | Accounts store: `data/accounts.db` (sqlight)                                          | Each **Account** (uid, email, first and last name) and each link (**Workspace**, **Line**, **Team Member**, email), one email per **Line**; the dated log of **Shared** and **Private** | F43–F47                          | [ADR-0004](./docs/adr/0004-account-links-live-in-one-shared-accounts-db.md) |
| C7  | Access guard: Gleam module `bluebin/access` in C2                                     | Role of the **Account** in the **Line**, per-route role table, `teamMember` check, `404` for a **Private Line** on the API and the live stream                                          | F48–F50, F52, F53                | —                                                                           |
| C8  | Forward-auth headers: Traefik `authResponseHeaders` in the Coolify custom labels (C5) | Adds `X-authentik-email` and `X-authentik-name`, written by authentik only                                                                                                              | F44, F52                         | [ADR-0003](./docs/adr/0003-link-team-members-to-accounts-by-email.md)       |

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

### Blue Bin suggestion (F54, F55)

| Rank | Function                                     | Target                                                     | Watched on                                                                                          | If we miss it                                                                         |
| :--: | -------------------------------------------- | ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
|  1   | F55 the suggestion does not follow WIP (R11) | Suggestion stable when only the **Blue Bin** count changes | F38 before/after: p85 **Replenishment Time** without `held` pauses, around each **Blue Bin** change | Show the suggestion only when it is lower than the current count, as a Kaizen hint    |
|  2   | F55 shown for the **Work Stations**          | ≥ 5 passes reached in the first 2 weeks of a real **Line** | Count of "Not enough flow yet" in Design                                                            | Lower the minimum to 3 passes, and show the pass count larger                         |
|  3   | F54 / F55 cost of the Design payload         | ≤ 50 ms more                                               | Request duration in the log, before and after                                                       | Compute from the current-state tables at each pass end, not from the log at each read |

### Sign-in and access (G11, G12)

| Rank | Function                              | Target                             | Watched on                                                                                                                        | If we miss it                                                                                                               |
| :--: | ------------------------------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
|  1   | F48 / F50 access guard                | 0 leaks, 0 actions as someone else | A test that fails when a route has no role-table entry, one test for each role × route; `403` and `404` counts in the request log | Routes with no entry are refused by default; on a leak, a server setting turns links off and access goes back to owner-only |
|  2   | F43 link at the next sign-in          | 100 %                              | "Not linked yet" count in Design                                                                                                  | The owner sees the unlinked **Team Members** and fixes the email                                                            |
|  3   | Guard cost per request                | ≤ 5 ms                             | Request duration in the log, before and after                                                                                     | Cache the role for each **Account** and **Line** in memory, cleared when a link or the flag changes                         |
|  4   | F45 own **Assignments** after sign-in | 0 clicks                           | First screen after sign-in, in the SPA                                                                                            | A "My work" entry in the **Line** menu                                                                                      |

---

### Deployment and Release (F56–F60)

| Rank | Function                                                                        | Target                | Watched on                                                                                              | If we miss it                                                                         |
| :--: | ------------------------------------------------------------------------------- | --------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
|  1   | F34 **Lead Time** = **Touch Time** + **Stagnation Time**, ending at **Release** | exact                 | `measures_test`: a held **Piece** adds its wait to **Stagnation Time** and to nothing else              | The log is the truth: rebuild the measures from `piece_deployed` and `piece_released` |
|  2   | F56 deploy and release together                                                 | 1 click               | The SPA flow on the last **Blue Bin**, as for F30                                                       | **Deploy** stays the only button; **Deploy, hold** moves into a menu                  |
|  3   | F60 a **Demand** ends at its last **Release**                                   | exactly at that event | `demand_test` and `bluebin_test` on a **Demand** with all **Pieces** deployed and one held              | Recompute the **Demand** state from the events at start-up                            |
|  4   | F59 every held **Piece** visible                                                | 100 %, no click       | API test: the **Held for Release** list = the **Pieces** with `deployed_at` set and `released_at` empty | List the held **Pieces** on each row of the Demands view                              |

### Helpers (F14, F61–F64)

| Rank | Function | Target | Watched on | If we miss it |
| :--: | --- | --- | --- | --- |
| 1 | F63 the help ends with its cause | 0 **Helpers** after their **Rework** closes | `flow_test`: repair a **Rework** with two **Helpers**; the `helper` table is empty, two `helper_left` events, each **Helper**'s paused **Piece** active again | At start-up, remove the **Helpers** of closed **Reworks** and settle each one |
| 2 | F62 pause and resume | 100 %, no manual step | `flow_test`: a **Helper** holding a **Piece** joins; it pauses with the cause `helping`; they stop; it is active again | The **Helper** takes the paused **Piece** in hand again by hand (F20) |
| 3 | H29 the v2 → v3 step | 0 data lost | `db_test`: a v2 file with data opens as v3, with the same rows and the same schema as a new v3 file | Refuse the file as before [ADR-0006](./docs/adr/0006-additive-schema-changes-migrate.md), and wipe only on request |
| 4 | F61 who can help | 0 **Helpers** against the rules | `flow_test`: refuse a **Team Member** of a third **Work Station**, a **Rework** with no **Assignment**, and a second helped **Piece** | The API refuses with `409`; the SPA hides **Help** |
| 5 | F14 help from the warning | 1 click | The SPA: pull at the **Work Station** that found an open **Rework**, then "Help <assignee> on <Piece>" | **Help** on the **Rework** card stays, in 2 clicks |

## 9. Tradeoffs — Got / Paid / ADR

| ID  | Tradeoff                                                                                                       | Got                                                                                                         | Paid                                                                                      | ADR                                                              |
| --- | -------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| T1  | Flow events + current state in one transaction (H3), over current state only (H1) and full event sourcing (H2) | Full history; every measure can be recomputed; dated **Line** changes; simple, fast reads for daily screens | Two writes for each action that must stay consistent; the log grows forever               | [ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md) |
| T2  | Server-Sent Events (H5), over polling (H4) and WebSockets (H6)                                                 | Updates in less than 1 s; standard browser reconnect; one direction is all we need                          | One open connection for each screen; actions and updates use two channels                 | —                                                                |
| T3  | SQLite (C3), over Postgres                                                                                     | One file, real transactions, no database server; fits the one-writer flow of a team                         | Single writer: a move to Postgres when many teams share one instance (H3 does not change) | —                                                                |

| T4 | Account links only in a shared `accounts.db` (H8), over the email on the **Team Member** in the **Line** file plus an index (H7), and a scan of the **Line** files (H9) | One place for every **Account** and link; F46 and each access check are one indexed query; no copy to keep in sync | A link change is not in the **Line**'s transaction or flow log; a Reset or a removed **Team Member** leaves orphan links, so every read checks that the **Team Member** still exists | [ADR-0004](./docs/adr/0004-account-links-live-in-one-shared-accounts-db.md) |
| T5 | The owner's uid in the URL (H12), over a random **Workspace** id (H13) | No migration, no new table: the uid is already the directory name | The owner's authentik uid (a hash) shows in links, history and logs; a **Workspace** cannot move to another owner | — |
| T6 | **Replenishment Time** from the pull-in to the **Blue Bin** (H15), over the Toyota loop from the **Kanban** sent (H18) | Data that exists; no pairing of **Kanbans** to pulls; extra **Blue Bins** never hide a capacity problem | The suggestion is low for a **Work Station** whose **Kanbans** wait for a free **Team Member** (R12) | — |
| T7 | The last 20 passes, at least 5 (H15), over the last 7 days (H16) and the Measures period (H17) | Fresh on a fast **Line**, enough on a slow one; no hidden state in Design | Not the F10 window; lags a **Line** change by up to 20 passes (R13) | — |
| T8 | A cause on each `piece_paused`, and F55 without the `held` pauses, over a paused share in the hint, or **Touch Time** only | Cuts the WIP loop at its source, keeps **Rework** as a real loss | One more field on the event; old pauses with no cause count as `held` | — |
| T9 | A `released_at` column and a `piece_released` event (H19), over `held` and `released` states (H20) and a `release` table (H21) | Smallest change; **Lead Time** to **Release** and the hold wait come from data that the event log already carries | "Released together" is only a shared moment, with no record of the group | — |
| T10 | Squash to version 2 and wipe the workspaces (H22), over a migration step (H23, H24) | No migration code; the code says **Deployment** on disk and on the wire | All workspace data on bluebin.app, the **Public Workspace** included, is lost a second time in two days | — |
| T11 | An additive migration step v2 → v3 (H29), over a third wipe (H28) and a hidden `create table if not exists` (H30) | No data lost for a feature that only adds a table; the version still describes the schema | A migration path to keep and test for each version; "never migrate" becomes "migrate only what adds" | [ADR-0006](./docs/adr/0006-additive-schema-changes-migrate.md) |
| T12 | `helping` pauses count in F55 like `rework` (R14), over `held` (dropped) and a separate measure | The suggestion sees all the capacity lost to defects, on every **Work Station** the defect pulls people from | A **Work Station** whose **Team Members** help often gets a higher suggestion; the root cause is the defect, so F16 must show it | — |

### Tensions being watched (unresolved by design)

- **Single SQLite writer.** One instance serves one or a few teams. **Trigger to revisit:** many teams share one instance, or write latency breaks F17.
- **Standardized Work out of the app.** No Definition of Done per **Work Station**. **Trigger to revisit:** **Rework** shows that **Work Stations** disagree on what "done" means.
- **Acceptance of a whole Feature.** Each **Piece** is deployed alone; there is no **Demand**-level acceptance. **Trigger to revisit:** a **Client** cannot accept value one **Piece** at a time.
- **No personal notifications.** Only **Andons** interrupt. **Trigger to revisit:** stale **Assignments** (F33) stay above 5 %.
- **A Workspace cannot move to another owner** (T5). The owner's uid is the **Workspace** directory. **Trigger to revisit:** an owner leaves a team that keeps working.
- **The wall TV cannot act for linked Team Members** (R7). **Trigger to revisit:** stale **Assignments** (F33) above 5 % on teams with linked **Team Members**.
- **Orphan links after a Reset or a removed Team Member** (H8). Harmless, because a link counts only while its **Team Member** exists. **Trigger to revisit:** orphan links outnumber live ones, or a cleanup misses a case.
- **The Account's name is asked once, never synced from authentik** (F44). **Trigger to revisit:** people change their name in authentik and expect Bluebin to follow.
- **The suggestion assumes enough capacity** (T6, R12). **Trigger to revisit:** a **Work Station** at its suggested count still starves the one after it, while F10 does not flag it.
- **Past pauses have no cause** (T8). They all count as `held`, so old Rework pauses are dropped too, and the first suggestions run low. **Trigger to revisit:** a **Line** with much past **Rework** gets suggestions below its real need.
- **A held Demand stays in the Takt Time of the Line** (F60). Until its last **Release**, it makes the **Takt Time** of the **Line** shorter than the work left, so F10 and F55 are stricter during a hold; its **Takt Gap** cannot raise an **Andon**, because all its **Pieces** are deployed. **Trigger to revisit:** a team acts on bottleneck flags or **Blue Bin** suggestions that come only from held **Demands**.
- **"Released together" has no record of the group** (T9). **Trigger to revisit:** a team asks which **Pieces** went out in one **Release**, for example for release notes.
- **Help Downstream is not recorded as a Helper.** [CONTEXT.md](./CONTEXT.md) allows it, but F22 points at a **Work Station**, not at a **Piece**, so there is nothing to join yet. **Trigger to revisit:** a team asks who helps downstream, or **Starvation Time** stays high while people wait.
- **No measure of the help.** **Helpers** add people, not time, so no core measure changes. **Trigger to revisit:** a Kaizen asks how much of a stop had a **Helper**.

---

## 10. Inconsistencies spotted and fixed

- **Soft pull rules vs "never" in the glossary and in G2.** F6, F8 and F9 warn and do not block, but [CONTEXT.md](./CONTEXT.md) said a **Team Member** never starts work without a **Kanban**, and G2 said overproduction is impossible. Resolved: new term **Deviation** (a broken rule, with a required reason, visible at once); the glossary now says "only as a **Deviation**"; G2 now says "never silent".
- **Help Downstream target.** During the glossary session, Help Downstream was said to point at the **Work Station** with the most **Starvation Time**. A starved **Work Station** is downstream of the problem, not the problem. Resolved: F22 points at the nearest downstream **Work Station** that holds up the flow, which matches the **Help Downstream** definition.
- **Help Downstream sent people to a stopped Work Station.** `assignment.help_downstream` pointed any free **Team Member** upstream at a **Work Station** that "found a defect and waits for its Rework", but only the two **Work Stations** concerned can **Help the Rework**, so a **Team Member** of a third **Work Station** had nothing to do there. Resolved: F22 skips a **Work Station** stopped by its **Rework**; the **Team Members** of the **Work Station** that made the defect get **Help the Rework** through F19; the others wait, or help where a full **Blue Bin** holds up the flow.
- **Finish accepts a Piece under Rework.** `flow.finish` put a **Piece** with an open **Rework** in a **Blue Bin** with no trace, so the defect left the **Work Station** that found it while its **Rework** stayed open. Resolved (2026-11-08): finishing the **Piece** accepts the repair and closes its **Rework** (`rework_repaired` with `by: finish`), ends its help and frees its repairer. **Rework Time** ends at that moment and **First Pass Yield** still counts the defect. The holder of the **Piece** still gets **Help the Rework** as next thing until the repair.
- **Person vs Team Member.** [CONTEXT.md](./CONTEXT.md) renamed **Person** to **Team Member** (2026-11-06). Resolved everywhere: the code, the SPA text, the docs, and then in one hard rename the wire and the disk (`/api/team-members`, the JSON fields `teamMember`, `teamMemberId` and `teamMembers`, the `?teamMember=` link, the `team_member` and `station_team_member` tables, and the stored `team_member_*` changes). The schema then restarted from one version, with no data kept. Ids keep their `pe-` prefix.
- **Flow actions name any Team Member.** Each flow action took the **Team Member** from the request body, so any client acted as anyone. Resolved for the actions that name one (pull, **Andon**, close an **Andon**, **Assignment**): C7 checks it (F50). Open: finish, deliver, **Rework**, repair and make urgent name no **Team Member**, so a **Team Member** can do them on another one's **Piece**; and a linked **Team Member** cannot hand an **Assignment** to someone else, nor can the owner hand one to a linked **Team Member**.
- **Owner of the public Workspace.** [CONTEXT.md](./CONTEXT.md) said each **Workspace** has one owner **Account**, but the public **Workspace** of visitors who are not signed in had none, and everyone could change it. Resolved: the **Public Workspace** is the **Workspace** of one chosen **Account** (`akadmin`), which alone changes it; everyone else only looks. Its **Shared Lines** open with no sign-in by their look-only link (F53), like every other **Shared Line**. Superseded (2026-11-08): the **Public Workspace** is gone; the **Simulation** ([try.bluebin.app](https://try.bluebin.app)) runs the demo data in the visitor's page, with no server and no database.
- **Who sees a Shared Line.** [CONTEXT.md](./CONTEXT.md) said every **Account** able to open its **Workspace**, so only the **Team Members** of another **Line** there. Resolved (2026-11-07): anyone with its link, signed in or not, look-only. authentik lets the look-only paths through with no sign-in; with SSO on, a request with no uid then gets no **Workspace** (`401`), so a path that climbs out of `/api/s/` opens nothing.
- **Diagrams lag G11 and G12.** The TPS house (§1) and the House of Quality do not show G11, G12, F43–F52, F54, F55 or F61–F64, nor the new words of G4 and G5. Open: redraw both after the build.
- **"A user has one workspace for now".** The comment in `backend/src/bluebin/workspace.gleam` and the README's "Sign-in and Workspaces" said the **Workspace** comes only from `X-authentik-uid`. Resolved with C7 and H12: the owner's uid in the URL opens another **Workspace**.
- **F9 and the automatic pause.** F9 also warned before a second active **Assignment**, but taking an **Assignment** pauses the current one automatically, so a second active one cannot happen. Resolved: F9 covers only the second **Piece** in a **Blue Bin**.

- **Station Lead Time without pauses.** The relationship in [CONTEXT.md](./CONTEXT.md) said **Station Lead Time** = **Touch Time** + the wait in the **Blue Bin**, but the code counts pauses in it too, as **Stagnation Time**. Resolved (2026-11-07): **Station Lead Time** = **Replenishment Time** + the wait in the **Blue Bin**, and **Replenishment Time** = **Touch Time** + pauses.
- **Kanbans have no identity.** `kanban_sent` and `kanban_spent` name only the **Work Station**, so a **Kanban** cannot be followed to the **Piece** it brought. Left open: H15 does not need it; a Toyota-loop measure (H18) would.
- **"Production" had no definition.** The glossary used it for both the end of the **Line** and the **Client** getting the **Piece**. Resolved in [CONTEXT.md](./CONTEXT.md): **Deployment** and **Release** are two events; G3, F2, F4, F5, F18, F20, F32 and F34 now name one of them.
- **The code says `produced`, the glossary says Deployment.** `piece.state = 'produced'`, `produced_at`, `piece_reached_production` and `piecesProduced`. Resolved by H22: renamed to `deployed` on disk and on the wire.
- **"Release" in the Backlog meant a manual reorder.** The Backlog button said "Release this Piece before its turn". Resolved: the button title says "Move this Piece to the top of the Backlog", the warning says "Moving this Piece to the top", F24 says "leave the **Backlog**", and **Release** keeps its glossary meaning.
- **"A new version 1" would not refuse old files.** H22 first said to squash to a new version 1, but a file at the old version 1 would pass the version check and then fail on the renamed columns. Resolved: the schema goes to version 2.

---

## 11. Build order — G11 and G12

Each slice ships alone, from the SPA to the store, and leaves production safe. A slice that opens a **Workspace** to another **Account** ships with its guard, never before it.

| Slice | Name                                       | Functions and components         | What ships                                                                                                                                                                                                    | Done when                                                                  |
| :---: | ------------------------------------------ | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
|   1   | The **Account** (built)                    | C6, C8, F44, F52, R10            | `data/accounts.db` with each **Account**; `X-authentik-email` and `X-authentik-name` in the Coolify labels and the Vite dev proxy; the SSO setting (`BLUEBIN_SSO=on`); the first sign-in screen               | Each **Account** gives its name once; with SSO off, no **Account** is made |
|   2   | Link a **Team Member** by email (built)    | F43, F47, R8                     | An email and "not linked yet" on each **Team Member** in Design; the link made at the next sign-in, and the dated log of link changes (R8); the **Account**'s name on each linked **Team Member**             | 100 % linked at the next sign-in (§8)                                      |
|   3   | Open other **Workspaces**, guarded (built) | H12, C7, F46, F48, F49, F50, F51 | `/api/w/<owner-uid>/lines/<id>/…` and `/w/<owner-uid>/lines/<id>/<view>`; the access guard on every **Line** route and the live stream; the **Line** menu grouped by **Workspace**; **Shared** or **Private** | 0 leaks, 0 actions as someone else (§8); one test for each role × route    |
|   4   | My work after sign-in (built)              | F45                              | The signed-in **Team Member**'s own **Assignments** as the first screen                                                                                                                                       | 0 clicks (§8)                                                              |
|   5   | **Shared Lines**, look-only (built)        | F53                              | `/s/<owner-uid>/lines/<id>/<view>` and `/api/s/<owner-uid>/lines/<id>/…` (`GET` only, no identity read); authentik unauthenticated paths for them; **Copy look-only link** in the **Line** menu               | 0 changes by anyone else                                                   |

Why this order:

- **Slice 1 first.** Every other Function of G11 and G12 needs an **Account**. It changes no access, so it is safe alone. The dated log of link changes moved to slice 2, which makes the first link.
- **Slice 3 is one deploy.** Today each flow action takes the **Team Member** from the request body (§10). URLs that open another **Workspace** without the guard let any client act as anyone.
- **Slice 4 after slice 3.** The first screen must know the **Line** of the **Team Member**, and that **Line** can be in another owner's **Workspace**.

---

## 12. Build order — Blue Bin suggestion (F54, F55)

| Slice | Name                                       | Functions and components | What ships                                                                                                              | Done when                                                   |
| :---: | ------------------------------------------ | ------------------------ | ----------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
|   1   | The cause of a pause (built)               | R11, T8, C2              | `piece_paused` names its cause: `rework` (F13) or `held` (F32); a past pause with no cause reads as `held`              | Each new pause has a cause; the measures still add up (F34) |
|   2   | **Replenishment Time** in Measures (built) | F54, H15, C1, C2         | p85 **Replenishment Time** for each **Work Station**, in the Measures period, next to **Station Lead Time**             | Value for each **Work Station** with ≥ 5 passes             |
|   3   | Suggested **Blue Bins** in Design (built)  | F55, H15, C1, C2         | The suggestion and its inputs in the Design payload; the neutral hint under the **Blue Bin** input, one click to set it | §8 Blue Bin suggestion, rows 1–3                            |

Why this order: slice 1 must ship first, so that pauses carry a cause before the suggestion reads them; every day without it adds untagged pauses. Slice 2 lets the owner check the numbers before Design suggests anything.

---

## 13. Build order — Deployment and Release (G13)

| Slice | Name                              | Functions and components       | What ships                                                                                                                                                   | Done when                                                       |
| :---: | --------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------- |
|   1   | Speak Deployment (built)          | H22, C2, C3, C1                | The schema at version 2, with no migration step; `produced` → `deployed` on disk, on the wire and in the SPA; no change in behaviour                         | `gleam test` and the SPA typecheck pass with no `produced` left |
|   2   | The Release event (built)         | F56, F60, F5, F34, H19, C2, C1 | `released_at` and `piece_released`; **Deploy** writes both; **Lead Time** and On-Time Delivery end at **Release**; a **Demand** ends at its last **Release** | §8 rows 1 and 3 pass                                            |
|   3   | Hold and Held for Release (built) | F57, F58, F59, C1, C2          | **Deploy, hold**; the **Held for Release** zone in the Line view; **Release** and **Release all**; `POST /api/release`                                       | §8 rows 2 and 4 pass                                            |
|   4   | Backlog wording (built)           | C1 `BacklogView`               | "Move this Piece to the top"                                                                                                                                 | No "Release" left for a reorder                                 |

Why this order: slice 1 is a pure rename, so the tests prove it alone before any behaviour moves. Slice 2 changes the measures with no new UI: every **Piece** is still released at its **Deployment**, so the numbers must stay the same. Slice 3 adds the only new behaviour. The wipe of `/app/data/workspaces` happens once, at the deploy of all four slices together (T10).

---

## 14. Build order — Helpers (F14, F19, F22, F61–F64)

| Slice | Name | Functions and components | What ships | Done when |
| :---: | --- | --- | --- | --- |
| 1 | The **Helper** record (built) | H29, F61, F62, F63, R14, C2, C3, C7 | The v2 → v3 step and the `helper` table; `help_the_rework` and `stop_helping`; closing a **Rework** ends its help; `settle` pauses with the cause `helping`; `measures` keeps `helping` like `rework`; `POST /api/help` and `POST /api/help/stop` | §8 Helpers rows 1–4 pass; `pnpm sim:test` passes |
| 2 | The next thing (built) | F19, F22, C2 `assignment`, C1 `NextThingView` | `HelpTheRework` before `HelpDownstream`, and instead of finishing a **Piece** in hand that is under **Rework**; F22 skips a **Work Station** stopped by its **Rework**; "Helping <assignee> on <Piece>" with **Stop helping** | A **Team Member** of the **Work Station** that made the defect sees **Help the Rework**; one of a third **Work Station** sees no stopped target |
| 3 | **Helpers** on the **Line** (built) | F61, F63, F64, C1 `WorkStationCard`, C2 `line` | "+ Help…" on a **Rework** item, for the **Team Members** in its `canHelp`, the **Helpers**' names on the **Rework** and the **Piece** in hand, **Stop helping** | **Help** in 2 clicks from the **Line** view |
| 4 | Help from the stop warning (built) | F14, C1 `DeviationDialog`, C1 `LineView`, C2 `line` | "Help <assignee> on <Piece>" first, "Go on anyway (Deviation)" second; the warning says a free **Blue Bin** does not change the stop | §8 Helpers row 5 |

Why this order: slice 1 holds the rules and the data, and its tests prove them with no UI. The Simulation (try.bluebin.app) runs the same C2 code compiled to JavaScript, so slice 1 must compile on both targets. Slices 2 and 3 make the action reachable. Slice 4 changes the warning last, because its first action needs slice 1.

---

## How to keep this honest

- When a new ADR lands, add its components to the component map and re-score the affected rows.
- When a measurement returns numbers, update the targets and the performance budget.
- Goals change rarely; functions change with each release; matrices are recomputed when either side changes.
- If a section becomes empty after edits, delete it.
