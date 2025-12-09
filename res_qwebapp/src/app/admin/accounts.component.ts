import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

interface Account {
  id: number;
  name: string;
  gender: string;
  address: string;
  birthdate: string;
  phone: string;
  validIdUrl: string;
}

@Component({
  selector: 'app-accounts',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './accounts.html',
})
export class AccountsComponent {
  accounts: Account[] = [
    {
      id: 1,
      name: 'Juan Dela Cruz',
      gender: 'Male',
      address: 'Angeles City',
      birthdate: 'Oct 09, 1997',
      phone: '0917 123 4567',
      validIdUrl: 'assets/images/license.png',  
    },
    {
      id: 2,
      name: 'Maria Santos',
      gender: 'Female',
      address: 'Mabalacat City',
      birthdate: 'Apr 21, 1999',
      phone: '0918 987 6543',
      validIdUrl: 'assets/images/license2.jpg',   
    },
  ];

  selected: Account | null = this.accounts[0];

  select(account: Account) {
    this.selected = account;
  }

  ban(account: Account) {
    console.log('Ban account', account);
    alert(`Banned account: ${account.name}`);
  }
}
