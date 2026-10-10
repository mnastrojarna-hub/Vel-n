import { Text } from 'recharts'

// Popisky osy X sloupcových grafů Analýzy na telefonu (< 768 px): delší názvy stavů se
// místo vzájemného překrývání zalomí do více řádků. Desktop i tablet dál používají
// původní tick beze změny (komponenta se předává jen při PHONE_QUERY).
export const PHONE_QUERY = '(max-width: 767px)'

export function WrapTick({ x, y, payload, width = 70, fontSize = 10 }) {
  return (
    <Text x={x} y={y} width={width} textAnchor="middle" verticalAnchor="start" fontSize={fontSize} fill="#666">
      {payload?.value}
    </Text>
  )
}

// Koláče s legendou vpravo: na telefonu by svislá legenda vpravo překryla výseče, proto
// jde pod graf (výchozí vodorovná legenda Recharts) a graf je o něco vyšší (phoneH).
// Tablet i desktop dostanou původní props beze změny.
export const sideLegend = isPhone => (isPhone ? {} : { layout: 'vertical', align: 'right', verticalAlign: 'middle' })
