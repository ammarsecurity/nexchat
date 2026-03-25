/** Cached public SiteContent flags (one in-flight request per key per session). */

let codeConnectInflight = null
let codeConnectResolved = null

function parseEnabled(content) {
  if (content === undefined || content === null || String(content).trim() === '') return true
  const c = String(content).toLowerCase()
  return c === 'true' || c === '1'
}

/**
 * @param {import('axios').AxiosInstance} api
 * @returns {Promise<boolean>}
 */
export async function getCodeConnectFeaturesEnabled(api) {
  if (codeConnectResolved !== null) return codeConnectResolved
  if (!codeConnectInflight) {
    codeConnectInflight = api
      .get('SiteContent/code_connect_features_enabled', { skipGlobalLoader: true })
      .then(({ data }) => {
        const enabled = parseEnabled(data?.content)
        codeConnectResolved = enabled
        return enabled
      })
      .catch(() => {
        codeConnectResolved = true
        return true
      })
      .finally(() => {
        codeConnectInflight = null
      })
  }
  return codeConnectInflight
}

/** For tests or after admin toggles without reload (optional). */
export function resetCodeConnectFeaturesCache() {
  codeConnectResolved = null
  codeConnectInflight = null
}
