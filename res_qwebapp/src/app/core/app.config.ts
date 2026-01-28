import { ApplicationConfig, importProvidersFrom } from '@angular/core';
import { provideRouter } from '@angular/router';
import { routes } from './app.routes';
import { FontAwesomeModule } from '@fortawesome/angular-fontawesome';
import './config/firebase.config'; // Initialize Firebase
import { FirestoreService } from './services/firestore.service';

export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(routes),
    importProvidersFrom(FontAwesomeModule),
    FirestoreService,
  ],
};
