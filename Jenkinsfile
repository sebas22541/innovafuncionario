pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  stages {
    stage('Backend check') {
      steps {
        dir('backend') {
          sh 'npm ci'
          sh 'npm run check'
        }
      }
    }

    stage('Docker build') {
      steps {
        sh 'docker compose -f docker-compose-prod.yml --env-file .env.docker build'
      }
    }

    stage('Deploy') {
      steps {
        sh 'docker compose -f docker-compose-prod.yml --env-file .env.docker up -d'
      }
    }
  }
}
