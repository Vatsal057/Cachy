/**
 * Settings — Flutter has no separate settings screen; everything lives in the
 * "You" tab, so /settings just forwards there.
 */
import { Navigate } from 'react-router-dom';

export default function SettingsScreen() {
  return <Navigate to="/profile" replace />;
}
