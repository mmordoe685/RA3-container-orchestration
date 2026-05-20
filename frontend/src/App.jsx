import { useEffect, useState } from 'react'

const API = '/api/items'

export default function App () {
  const [items, setItems]             = useState([])
  const [title, setTitle]             = useState('')
  const [description, setDescription] = useState('')
  const [loading, setLoading]         = useState(true)
  const [error, setError]             = useState(null)

  useEffect(() => { fetchItems() }, [])

  async function fetchItems () {
    setLoading(true)
    setError(null)
    try {
      const res = await fetch(API)
      if (!res.ok) throw new Error('HTTP ' + res.status)
      setItems(await res.json())
    } catch (e) {
      setError('No se ha podido contactar con el backend: ' + e.message)
    } finally {
      setLoading(false)
    }
  }

  async function createItem (e) {
    e.preventDefault()
    if (!title.trim()) return
    try {
      const res = await fetch(API, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ title, description })
      })
      if (!res.ok) throw new Error('HTTP ' + res.status)
      setTitle('')
      setDescription('')
      await fetchItems()
    } catch (e) {
      setError('Error al crear: ' + e.message)
    }
  }

  async function deleteItem (id) {
    try {
      const res = await fetch(`${API}/${id}`, { method: 'DELETE' })
      if (!res.ok) throw new Error('HTTP ' + res.status)
      await fetchItems()
    } catch (e) {
      setError('Error al borrar: ' + e.message)
    }
  }

  return (
    <div className="container">
      <header>
        <h1>RA3 - Container Orchestration Demo</h1>
        <p className="subtitle">
          React (frontend) &rarr; Nginx (reverse proxy) &rarr; Spring Boot (backend) &rarr; MySQL
        </p>
      </header>

      <section className="card">
        <h2>Crear item</h2>
        <form onSubmit={createItem}>
          <input
            type="text"
            placeholder="Titulo (obligatorio)"
            value={title}
            onChange={e => setTitle(e.target.value)}
            maxLength={120}
            required
          />
          <textarea
            placeholder="Descripcion (opcional)"
            value={description}
            onChange={e => setDescription(e.target.value)}
            maxLength={1000}
            rows={3}
          />
          <button type="submit">Anadir</button>
        </form>
      </section>

      <section className="card">
        <div className="row">
          <h2>Items existentes</h2>
          <button className="refresh" onClick={fetchItems}>Refrescar</button>
        </div>

        {error && <div className="error">{error}</div>}
        {loading && <p>Cargando...</p>}

        {!loading && items.length === 0 && <p>Aun no hay items.</p>}

        <ul className="items">
          {items.map(it => (
            <li key={it.id}>
              <div>
                <strong>#{it.id} &mdash; {it.title}</strong>
                {it.description && <p>{it.description}</p>}
                {it.createdAt && <small>{it.createdAt}</small>}
              </div>
              <button className="del" onClick={() => deleteItem(it.id)}>Borrar</button>
            </li>
          ))}
        </ul>
      </section>

      <footer>
        <small>RA3 / 2DAW &mdash; Despliegue de Aplicaciones Web</small>
      </footer>
    </div>
  )
}
