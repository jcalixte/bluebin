/** A Demand as the API reports it, with its Takt Time and Takt Gap. */
export type Demand = {
  id: string
  label: string
  client: string
  dueOn: string
  piecesAsked: number
  piecesProduced: number
  workingDaysTotal: number
  workingDaysElapsed: number
  taktTimeHours: number
  taktGap: number
  andon: boolean
}
