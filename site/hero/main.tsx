import { createRoot } from 'react-dom/client'
import { DeckTermHero } from './DeckTermHero'

const host = document.getElementById('hero-demo')
if (host) createRoot(host).render(<DeckTermHero />)
