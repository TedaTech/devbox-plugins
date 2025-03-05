#!/usr/bin/env bash
set -e

# Function to detect CI environment
detect_ci_environment() {
  if [ -n "$GITHUB_ACTIONS" ]; then
    echo "github"
  elif [ -n "$GITLAB_CI" ]; then
    echo "gitlab"
  else
    echo "unknown"
  fi
}

# Load environment variables from .env and .env.local if they exist
if [ -f .env ]; then
  echo "Loading variables from .env"
  source .env
fi

if [ -f .env.local ]; then
  echo "Loading variables from .env.local"
  source .env.local
fi

# Set default values if not already set
if [ -z "$APP_REPOSITORY" ]; then
  CI_ENV=$(detect_ci_environment)
  
  case $CI_ENV in
    github)
      # For GitHub, use the GitHub Container Registry format
      APP_REPOSITORY="${GITHUB_REPOSITORY_OWNER:-organization}/$(basename ${GITHUB_REPOSITORY:-app})"
      ;;
    gitlab)
      # For GitLab, use the GitLab Container Registry format
      APP_REPOSITORY="${CI_REGISTRY_IMAGE:-registry.gitlab.com/organization/app}"
      ;;
    *)
      # Default fallback
      APP_REPOSITORY="organization/app"
      ;;
  esac
  
  echo "Setting default APP_REPOSITORY: $APP_REPOSITORY"
fi

if [ -z "$APP_TAG" ]; then
  CI_ENV=$(detect_ci_environment)
  
  case $CI_ENV in
    github)
      if [[ "$GITHUB_REF" == refs/tags/* ]]; then
        # This is a tag/release
        APP_TAG="${GITHUB_REF#refs/tags/}"
      else
        # Use short commit SHA
        APP_TAG="${GITHUB_SHA:0:7}"
      fi
      ;;
    gitlab)
      if [ -n "$CI_COMMIT_TAG" ]; then
        # This is a tag/release
        APP_TAG="$CI_COMMIT_TAG"
      else
        # Use short commit SHA
        APP_TAG="${CI_COMMIT_SHORT_SHA:-unknown}"
      fi
      ;;
    *)
      # Default fallback - use current date and time
      APP_TAG="$(date +%Y%m%d-%H%M%S)"
      ;;
  esac
  
  echo "Setting default APP_TAG: $APP_TAG"
fi

# Login to Docker registry if in GitHub Actions
if [ -n "$GITHUB_ACTIONS" ]; then
  echo "Logging in to GitHub Container Registry"
  echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin
fi

# Execute Docker build and push commands
echo "Building Docker image: $APP_REPOSITORY:$APP_TAG"
docker build -t "$APP_REPOSITORY:$APP_TAG" .

echo "Pushing Docker image: $APP_REPOSITORY:$APP_TAG"
docker push "$APP_REPOSITORY:$APP_TAG"

# Also tag as latest if this is a release
if [[ "$APP_TAG" != *-* ]] && [[ "$APP_TAG" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo "Tagging as latest (release detected)"
  docker tag "$APP_REPOSITORY:$APP_TAG" "$APP_REPOSITORY:latest"
  docker push "$APP_REPOSITORY:latest"
fi

echo "Docker build and push completed successfully"
