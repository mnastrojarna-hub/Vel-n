export default function Card({ children, className = '', style = {} }) {
  return (
    <div
      className={`bg-white rounded-card shadow-card ${className}`}
      style={{ padding: 20, ...style }}
    >
      {children}
    </div>
  )
}
