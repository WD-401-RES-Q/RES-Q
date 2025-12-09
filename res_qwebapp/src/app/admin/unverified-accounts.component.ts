import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

interface UnverifiedAccount {
  id: number;
  name: string;
  gender: string;
  address: string;
  birthdate: string;
  phone: string;
  validIdUrl: string;
}

@Component({
  selector: 'app-unverified-accounts',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './unverified-accounts.html',
})
export class UnverifiedAccountsComponent {
  accounts: UnverifiedAccount[] = [
    {
      id: 1,
      name: 'Patrick Dela Cruz',
      gender: 'Male',
      address: 'Angeles City',
      birthdate: 'Jan 20, 2001',
      phone: '0917 000 0001',
      validIdUrl: 'assets/images/license.png',
    },
    {
      id: 2,
      name: 'Karla Mendoza',
      gender: 'Female',
      address: 'Mabalacat City',
      birthdate: 'May 10, 2000',
      phone: '0917 000 0002',
      validIdUrl: 'assets/images/license2.jpg',
    },
  ];

  approve(acc: UnverifiedAccount) {
    console.log('Approve account', acc);
    alert(`Approved account: ${acc.name}`);
  }

  reject(acc: UnverifiedAccount) {
    console.log('Reject account', acc);
    alert(`Rejected account: ${acc.name}`);
  }
}
