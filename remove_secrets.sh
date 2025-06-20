#!/bin/bash
set -e

# Ensure we're in the repo root
cd "$(git rev-parse --show-toplevel)"

echo "Creating backup branch before removing secrets (if it doesn't exist)..."
if git show-ref --quiet refs/heads/backup_before_secret_removal; then
  echo "Backup branch already exists, skipping backup creation"
else
  git checkout -b backup_before_secret_removal
  git checkout main
fi

# Ensure we're on the main branch
if [[ $(git branch --show-current) != "main" ]]; then
  echo "Switching to main branch..."
  git checkout main
fi

echo "Removing secrets from Git history using git-filter-repo..."

# Use git-filter-repo to remove specific secrets from the history
/home/thomas/Repositories/KubernetesLab/.venv/bin/python -m git_filter_repo \
  --replace-text <(cat <<EOF
rVSPZU!gmk7cqbHZ!v==><REDACTED_PASSWORD>
ghp_your_token_here==><REDACTED_GITHUB_TOKEN>
secure-bgp-password==><REDACTED_BGP_PASSWORD>
EOF
) \
  --force

echo ""
echo "✅ Secrets have been removed from the Git history!"
echo ""
echo "⚠️  IMPORTANT: You will need to force push these changes:"
echo "git push origin main --force"
echo ""
echo "⚠️  All team members will need to re-clone the repository or run:"
echo "git fetch origin && git reset --hard origin/main"
echo ""
echo "A backup branch 'backup_before_secret_removal' has been created locally"
echo "in case you need to reference the original history."
