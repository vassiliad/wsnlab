#include <iostream>
#include <vector>
#include <set>
#include <cstdlib>

int connect_nodes( int n1, int n2, std::vector< std::set<int> > &nodes, int maxc)
{ 
  if ( nodes[n1].size() == maxc || nodes[n2].size() == maxc )
    return 1;
  
  if ( n1 == n2 )
    return 1;

  nodes.at(n1).insert(n2);
  nodes.at(n2).insert(n1);

  std::cout << n1 << " " << n2 <<  std::endl;
  
  return 0;
}

int main( int argc, char* argv[])
{
  int number, minc, maxc, i;
  int connectivity;
  std::vector< std::set<int> > nodes;

  if ( argc != 4 ) {
    std::cout << "Usage :" << std::endl;
    std::cout << "\t" << argv[0] << " <number_of_nodes> <min_connectivity> <max_connectivity>" << std::endl;
    return 1;
  }
  
  number = atoi(argv[1]);
  minc   = atoi(argv[2]);
  maxc   = atoi(argv[3]);

  if ( number <= 0 || minc <= 0 || maxc <= 0 ) {
    std::cout << "Usage :" << std::endl;
    std::cout << "\t" << argv[0] << " <number_of_nodes> <min_connectivity> <max_connectivity>" << std::endl;
    return 1;
  }

  srand(time(0));
  
  nodes.reserve(number);

  std::vector<int> network;

  for ( i=0; i<number; i++ ) {
    nodes.push_back(std::set<int>());
    network.push_back(i);
  }



  for ( i=0; i<number; i++ ) {
    std::vector<int> t = network;

    connectivity = minc + rand()%(maxc-minc+1);

    while (nodes[i].size() < connectivity ) {
      int n;
      
      if ( t.size() == 0 ) {
        std::cout << "- Error! Current topology cannot be completed." << std::endl;
        return 0;
      }

      n = rand()%t.size();
      connect_nodes(i, t[n], nodes, maxc);
      t.erase(t.begin()+n);
    }
  }

  return 0;
}

